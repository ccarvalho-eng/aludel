defmodule Mix.Tasks.Aludel.Eval do
  @moduledoc """
  Runs one Aludel evaluation suite and emits machine-readable JSON.

      mix aludel.eval \
        --suite-id SUITE_ID \
        --prompt-version-id PROMPT_VERSION_ID \
        --provider-id PROVIDER_ID

  The task exits unsuccessfully when arguments or targets are invalid, execution
  cannot complete, or the active suite quality policy does not pass. Suites
  without a quality policy retain the all-test-cases-must-pass behavior.
  """

  @shortdoc "Runs an Aludel suite and emits JSON"
  @requirements ["app.start"]

  use Mix.Task

  alias Aludel.Evals
  alias Aludel.Prompts
  alias Aludel.Providers
  alias Decimal

  @schema_version 1
  @switches [suite_id: :string, prompt_version_id: :string, provider_id: :string]
  @required_options [:suite_id, :prompt_version_id, :provider_id]

  @impl Mix.Task
  def run(args) do
    case args |> parse_options() |> execute() do
      {:ok, %{status: "passed"} = payload} ->
        emit(payload)

      {:ok, payload} ->
        emit(payload)
        Mix.raise("Evaluation did not pass")

      {:error, error} ->
        emit(error_payload(error))
        Mix.raise(error.message)
    end
  end

  defp parse_options(args) do
    case OptionParser.parse(args, strict: @switches) do
      {options, [], []} -> validate_required_options(options)
      {_options, _positional, _invalid} -> {:error, cli_error("invalid_arguments", usage())}
    end
  end

  defp validate_required_options(options) do
    missing_options = Enum.reject(@required_options, &Keyword.has_key?(options, &1))

    if missing_options == [] do
      {:ok, Map.new(options)}
    else
      missing_flags = Enum.map_join(missing_options, ", ", &option_flag/1)
      {:error, cli_error("invalid_arguments", "Missing required options: #{missing_flags}")}
    end
  end

  defp execute({:error, error}) do
    {:error, error}
  end

  defp execute({:ok, options}) do
    with {:ok, suite} <- fetch_target("suite", fn -> Evals.get_suite!(options.suite_id) end),
         {:ok, prompt_version} <-
           fetch_target("prompt_version", fn ->
             Prompts.get_prompt_version!(options.prompt_version_id)
           end),
         {:ok, provider} <-
           fetch_target("provider", fn -> Providers.get_provider!(options.provider_id) end),
         :ok <- validate_prompt_version(suite, prompt_version),
         {:ok, suite_run} <- execute_suite(suite, prompt_version, provider) do
      {:ok, suite_run_payload(suite_run)}
    end
  end

  defp fetch_target(resource, fetch) do
    {:ok, fetch.()}
  rescue
    _error in [Ecto.NoResultsError, Ecto.Query.CastError] ->
      {:error, cli_error("#{resource}_not_found", "#{resource} was not found")}
  end

  defp validate_prompt_version(suite, prompt_version) do
    if prompt_version.prompt_id == suite.prompt_id do
      :ok
    else
      {:error,
       cli_error(
         "prompt_version_mismatch",
         "prompt_version does not belong to the suite prompt"
       )}
    end
  end

  defp execute_suite(suite, prompt_version, provider) do
    case Evals.execute_suite(suite, prompt_version, provider) do
      {:ok, suite_run} ->
        {:ok, suite_run}

      {:error, _reason} ->
        {:error, cli_error("execution_failed", "Suite execution could not be persisted")}
    end
  rescue
    _error ->
      {:error, cli_error("execution_failed", "Suite execution failed")}
  catch
    _kind, _reason ->
      {:error, cli_error("execution_failed", "Suite execution failed")}
  end

  defp suite_run_payload(suite_run) do
    total = suite_run.passed + suite_run.failed
    status = evaluation_status(suite_run, total)

    %{
      type: "aludel_eval",
      schema_version: @schema_version,
      status: status,
      suite_run_id: suite_run.id,
      suite_id: suite_run.suite_id,
      prompt_version_id: suite_run.prompt_version_id,
      provider_id: suite_run.provider_id,
      quality_policy: suite_run.quality_policy_result,
      summary: %{
        passed: suite_run.passed,
        failed: suite_run.failed,
        total: total,
        pass_rate: pass_rate(suite_run.passed, total),
        avg_score: decimal_to_string(suite_run.avg_score),
        avg_cost_usd: decimal_to_string(suite_run.avg_cost_usd),
        avg_latency_ms: suite_run.avg_latency_ms
      },
      results: Enum.map(suite_run.results, &result_payload/1)
    }
  end

  defp evaluation_status(%{quality_policy_result: %{"status" => status}}, _total)
       when status in ["passed", "failed", "invalid", "unavailable"] do
    status
  end

  defp evaluation_status(suite_run, total) do
    if suite_run.failed == 0 and total > 0, do: "passed", else: "failed"
  end

  defp result_payload(result) do
    %{
      test_case_id: result["test_case_id"],
      test_case_metadata: result["test_case_metadata"],
      status: if(result["passed"], do: "passed", else: "failed"),
      passed: result["passed"],
      score: result["score"],
      output: result["output"],
      assertion_results: Map.get(result, "assertion_results", []),
      input_tokens: result["input_tokens"],
      output_tokens: result["output_tokens"],
      cost_usd: result["cost_usd"],
      latency_ms: result["latency_ms"]
    }
  end

  defp error_payload(error) do
    %{
      type: "aludel_eval",
      schema_version: @schema_version,
      status: "error",
      error: error
    }
  end

  defp cli_error(code, message) do
    %{code: code, message: message}
  end

  defp pass_rate(_passed, 0) do
    0.0
  end

  defp pass_rate(passed, total) do
    Float.round(passed / total * 100, 2)
  end

  defp decimal_to_string(nil) do
    nil
  end

  defp decimal_to_string(%Decimal{} = decimal) do
    Decimal.to_string(decimal, :normal)
  end

  defp emit(payload) do
    payload
    |> Jason.encode!()
    |> Mix.shell().info()
  end

  defp option_flag(option) do
    "--#{option |> Atom.to_string() |> String.replace("_", "-")}"
  end

  defp usage do
    "Usage: mix aludel.eval --suite-id ID --prompt-version-id ID --provider-id ID"
  end
end
