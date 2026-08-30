defmodule Aludel.Execution.Artifact do
  @moduledoc false

  alias Aludel.Prompts.PromptVersion
  alias Aludel.Providers.Provider

  @schema_version 1
  @max_error_length 4_000

  @spec start_native(map(), String.t(), [map()]) :: map()
  def start_native(request, rendered_prompt, documents) do
    start(
      "native",
      "llm_call",
      request,
      documents,
      %{"rendered_prompt" => rendered_prompt}
    )
  end

  @spec start_callback(map(), map()) :: map()
  def start_callback(request, callback_input) do
    start(
      "callback",
      "executor_callback",
      request,
      callback_input.documents,
      %{
        "prompt_version" => normalize_prompt_version(callback_input.prompt_version, true)
      }
    )
  end

  @spec start_unavailable(map(), term()) :: map()
  def start_unavailable(request, reason) do
    start("unavailable", "execution", request, Map.get(request, :documents, []), %{})
    |> fail(reason)
  end

  @spec complete(map(), String.t(), map() | nil) :: map()
  def complete(artifacts, output, metadata) do
    update_step(artifacts, fn step ->
      step
      |> Map.put("status", "completed")
      |> Map.put("output", %{
        "raw" => output,
        "parsed" => parsed_output(output)
      })
      |> maybe_put("metadata", normalize_json(metadata))
    end)
  end

  @spec fail(map(), term()) :: map()
  def fail(artifacts, reason) do
    update_step(artifacts, fn step ->
      step
      |> Map.put("status", "failed")
      |> Map.put("error", %{
        "type" => error_type(reason),
        "message" => error_message(reason)
      })
    end)
  end

  @spec put_metrics(map(), [map()], number() | nil) :: map()
  def put_metrics(artifacts, metric_results, score) do
    update_step(artifacts, fn step ->
      Map.put(step, "metrics", %{
        "results" => normalize_json(metric_results),
        "score" => score
      })
    end)
  end

  defp start(mode, kind, request, documents, input_overrides) do
    %{
      "schema_version" => @schema_version,
      "steps" => [
        %{
          "index" => 0,
          "kind" => kind,
          "mode" => mode,
          "status" => "started",
          "input" =>
            request
            |> normalized_input(documents)
            |> Map.merge(input_overrides)
        }
      ]
    }
  end

  defp normalized_input(request, documents) do
    %{
      "kind" => request.kind |> Atom.to_string(),
      "prompt_version" => normalize_prompt_version(request.prompt_version, false),
      "variables" => normalize_json(request.variables),
      "provider" => normalize_provider(request.provider),
      "documents" => Enum.map(documents, &normalize_document/1),
      "metadata" => normalize_json(Map.get(request, :metadata, %{}))
    }
  end

  defp normalize_prompt_version(%PromptVersion{} = version, include_template?) do
    %{
      "id" => version.id,
      "version" => version.version
    }
    |> maybe_put("template", if(include_template?, do: version.template, else: nil))
  end

  defp normalize_prompt_version(version, include_template?) when is_map(version) do
    %{
      "id" => Map.get(version, :id),
      "version" => Map.get(version, :version)
    }
    |> maybe_put("template", if(include_template?, do: Map.get(version, :template), else: nil))
  end

  defp normalize_provider(%Provider{} = provider) do
    %{
      "id" => provider.id,
      "model" => provider.model,
      "type" => to_string(provider.provider)
    }
  end

  defp normalize_document(document) when is_map(document) do
    data = Map.get(document, :data)

    %{
      "name" => Map.get(document, :name) || Map.get(document, :filename),
      "content_type" => Map.get(document, :content_type),
      "size_bytes" => document_size(document, data)
    }
  end

  defp document_size(_document, data) when is_binary(data), do: byte_size(data)
  defp document_size(document, _data), do: Map.get(document, :size_bytes)

  defp parsed_output(output) do
    case Jason.decode(output) do
      {:ok, parsed} -> parsed
      {:error, _reason} -> nil
    end
  end

  defp normalize_json(nil), do: nil

  defp normalize_json(value) do
    case Jason.encode(value) do
      {:ok, encoded} -> Jason.decode!(encoded)
      {:error, _reason} -> nil
    end
  end

  defp update_step(%{"steps" => [step | remaining]} = artifacts, callback) do
    %{artifacts | "steps" => [callback.(step) | remaining]}
  end

  defp error_type(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp error_type(reason) when is_tuple(reason) do
    case Tuple.to_list(reason) do
      [type | _remaining] when is_atom(type) -> Atom.to_string(type)
      _other -> "execution_error"
    end
  end

  defp error_type(_reason), do: "execution_error"

  defp error_message(reason) do
    reason
    |> inspect(limit: 20, printable_limit: @max_error_length)
    |> String.slice(0, @max_error_length)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
