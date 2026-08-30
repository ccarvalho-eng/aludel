defmodule Aludel.Execution do
  @moduledoc """
  Shared execution boundary for native provider calls and host-app callbacks.
  """

  alias Aludel.Evals.TestCaseDocument
  alias Aludel.Execution.Artifact
  alias Aludel.Executor
  alias Aludel.LLM
  alias Aludel.Prompts.PromptVersion
  alias Aludel.Providers.Provider
  alias Aludel.Storage
  alias Ecto.Association.NotLoaded

  @default_document_load_timeout_ms 30_000

  @type request :: %{
          kind: :run | :suite,
          prompt_version: PromptVersion.t(),
          variables: map(),
          provider: Provider.t(),
          documents: [TestCaseDocument.t()],
          metadata: map()
        }

  @type result :: %{
          output: String.t(),
          input_tokens: non_neg_integer() | nil,
          output_tokens: non_neg_integer() | nil,
          latency_ms: non_neg_integer() | nil,
          cost_usd: float() | nil,
          metadata: map() | nil,
          artifacts: map()
        }

  @spec execute(request()) :: {:ok, result()} | {:error, term()}
  def execute(
        %{
          kind: kind,
          prompt_version: %PromptVersion{},
          variables: variables,
          provider: %Provider{}
        } = request
      )
      when kind in [:run, :suite] and is_map(variables) do
    case execute_with_artifacts(request) do
      {:ok, result} -> {:ok, result}
      {:error, reason, _artifacts} -> {:error, reason}
    end
  end

  @spec execute_with_artifacts(request()) ::
          {:ok, result()} | {:error, term(), map()}
  def execute_with_artifacts(
        %{
          kind: kind,
          prompt_version: %PromptVersion{} = prompt_version,
          variables: variables,
          provider: %Provider{} = provider
        } = request
      )
      when kind in [:run, :suite] and is_map(variables) do
    documents = Map.get(request, :documents, [])
    metadata = Map.get(request, :metadata, %{})

    with {:ok, loaded_documents} <- load_documents(documents),
         {:ok, execution_mode} <- Executor.configured_execution_mode() do
      case execution_mode do
        :callback ->
          execute_callback(
            request,
            kind,
            prompt_version,
            variables,
            provider,
            loaded_documents,
            metadata
          )

        _mode ->
          execute_native(request, prompt_version, variables, provider, loaded_documents)
      end
    else
      {:error, reason} -> {:error, reason, Artifact.start_unavailable(request, reason)}
    end
  end

  defp execute_native(request, prompt_version, variables, provider, documents) do
    rendered_prompt = render_template(prompt_version.template, variables)
    artifacts = Artifact.start_native(request, rendered_prompt, documents)

    llm_documents =
      Enum.map(documents, fn document ->
        %{data: document.data, content_type: document.content_type}
      end)

    opts = if llm_documents == [], do: [], else: [documents: llm_documents]

    case LLM.call(provider, rendered_prompt, opts) do
      {:ok, result} ->
        {:ok,
         %{
           output: result.output,
           input_tokens: result.input_tokens,
           output_tokens: result.output_tokens,
           latency_ms: result.latency_ms,
           cost_usd: result.cost_usd,
           metadata: nil,
           artifacts: Artifact.complete(artifacts, result.output, nil)
         }}

      {:error, reason} ->
        {:error, reason, Artifact.fail(artifacts, reason)}
    end
  end

  defp execute_callback(
         request,
         kind,
         prompt_version,
         variables,
         provider,
         documents,
         metadata
       ) do
    input = callback_input(kind, prompt_version, variables, provider, documents, metadata)
    artifacts = Artifact.start_callback(request, input)

    with {:ok, executor} <- Executor.configured_executor(),
         callback_result <- safe_invoke_callback(executor, input),
         {:ok, result} <- normalize_callback_result(callback_result) do
      {:ok,
       Map.put(result, :artifacts, Artifact.complete(artifacts, result.output, result.metadata))}
    else
      {:error, reason} -> {:error, reason, Artifact.fail(artifacts, reason)}
    end
  end

  defp safe_invoke_callback(executor, input) do
    executor.run(input)
  rescue
    error ->
      {:error, {:executor_crash, {:raise, error}}}
  catch
    :exit, reason ->
      {:error, {:executor_crash, {:exit, reason}}}

    kind, reason ->
      {:error, {:executor_crash, {kind, reason}}}
  end

  defp normalize_callback_result({:ok, result}) when is_map(result) do
    output = Map.get(result, :output)
    metadata = Map.get(result, :metadata)

    cond do
      not is_binary(output) ->
        {:error, {:invalid_executor_response, :missing_output}}

      invalid_metadata?(metadata) ->
        {:error, {:invalid_executor_response, :invalid_metadata}}

      true ->
        {:ok,
         %{
           output: output,
           input_tokens: optional_non_neg_integer(result, :input_tokens),
           output_tokens: optional_non_neg_integer(result, :output_tokens),
           latency_ms: optional_non_neg_integer(result, :latency_ms),
           cost_usd: optional_float(result, :cost_usd),
           metadata: metadata
         }}
    end
  end

  defp normalize_callback_result({:error, reason}), do: {:error, reason}
  defp normalize_callback_result(other), do: {:error, {:invalid_executor_response, other}}

  defp callback_input(kind, prompt_version, variables, provider, documents, metadata) do
    %{
      kind: kind,
      prompt_version: %{
        id: prompt_version.id,
        template: prompt_version.template,
        version: prompt_version.version
      },
      variables: variables,
      documents: documents,
      provider: %{
        id: provider.id,
        provider: provider.provider,
        model: provider.model,
        config: provider.config
      },
      metadata: metadata
    }
  end

  defp optional_non_neg_integer(result, key) do
    case Map.get(result, key) do
      value when is_integer(value) and value >= 0 -> value
      _ -> nil
    end
  end

  defp optional_float(result, key) do
    case Map.get(result, key) do
      value when is_float(value) -> value
      value when is_integer(value) -> value / 1
      _ -> nil
    end
  end

  defp invalid_metadata?(nil), do: false
  defp invalid_metadata?(metadata) when not is_map(metadata), do: true

  defp invalid_metadata?(metadata) do
    match?({:error, _reason}, Jason.encode(metadata))
  end

  defp load_documents([]), do: {:ok, []}

  defp load_documents(documents) when is_list(documents) do
    documents
    |> Task.async_stream(&load_document/1,
      timeout: document_load_timeout_ms(),
      on_timeout: :kill_task
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, document}}, {:ok, loaded_documents} ->
        {:cont, {:ok, [document | loaded_documents]}}

      {:ok, {:error, reason}}, _acc ->
        {:halt, {:error, reason}}

      {:exit, reason}, _acc ->
        {:halt, {:error, {:document_storage_error, :unknown_document, reason}}}
    end)
    |> case do
      {:ok, loaded_documents} -> {:ok, Enum.reverse(loaded_documents)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_document(%TestCaseDocument{} = document) do
    case safe_storage_read(document) do
      {:ok, data} ->
        {:ok,
         %{
           name: document.filename,
           content_type: document.content_type,
           data: data
         }}

      {:error, reason} ->
        {:error, {:document_storage_error, document.filename, reason}}
    end
  end

  defp load_document(%NotLoaded{}), do: {:error, :documents_not_loaded}

  defp safe_storage_read(document) do
    Storage.read(document)
  rescue
    error -> {:error, Exception.message(error)}
  catch
    :exit, reason -> {:error, reason}
  end

  defp render_template(template, variables) do
    Enum.reduce(variables, template, fn {key, value}, acc ->
      String.replace(acc, "{{#{key}}}", to_string(value))
    end)
  end

  defp document_load_timeout_ms do
    :aludel
    |> Application.get_env(:evals, [])
    |> Keyword.get(:document_load_timeout_ms, @default_document_load_timeout_ms)
  end
end
