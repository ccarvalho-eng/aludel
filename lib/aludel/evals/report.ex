defmodule Aludel.Evals.Report do
  @moduledoc """
  A normalized, versioned representation of an evaluation suite run.

  Reporters consume this struct instead of reading persistence schemas directly.
  This keeps output formats stable while the database representation evolves.
  Use `from_suite_run/1` to create a report and `to_map/1` when a plain map is
  needed for serialization.
  """

  alias Aludel.Evals.SuiteRun
  alias Decimal

  @schema_version 2
  @statuses ~w(passed failed invalid unavailable)

  @typedoc "The final quality decision: passed, failed, invalid, or unavailable."
  @type status :: String.t()
  @type t :: %__MODULE__{
          type: String.t(),
          schema_version: pos_integer(),
          status: status(),
          suite_run_id: binary(),
          suite_id: binary(),
          prompt_version_id: binary(),
          provider_id: binary(),
          quality_policy: map() | nil,
          summary: map(),
          results: [map()]
        }

  @enforce_keys [
    :status,
    :suite_run_id,
    :suite_id,
    :prompt_version_id,
    :provider_id,
    :summary,
    :results
  ]
  defstruct type: "aludel_eval",
            schema_version: @schema_version,
            status: nil,
            suite_run_id: nil,
            suite_id: nil,
            prompt_version_id: nil,
            provider_id: nil,
            quality_policy: nil,
            summary: nil,
            results: nil

  @doc """
  Builds a schema-version-2 report from a persisted suite run.

  A quality-policy result determines the report status when present. Runs
  without a policy pass only when they contain at least one result and every
  result passed.
  """
  @spec from_suite_run(SuiteRun.t()) :: t()
  def from_suite_run(%SuiteRun{} = suite_run) do
    total = suite_run.passed + suite_run.failed

    %__MODULE__{
      status: evaluation_status(suite_run, total),
      suite_run_id: suite_run.id,
      suite_id: suite_run.suite_id,
      prompt_version_id: suite_run.prompt_version_id,
      provider_id: suite_run.provider_id,
      quality_policy: suite_run.quality_policy_result,
      summary: %{
        "passed" => suite_run.passed,
        "failed" => suite_run.failed,
        "total" => total,
        "pass_rate" => pass_rate(suite_run.passed, total),
        "avg_score" => decimal_to_string(suite_run.avg_score),
        "avg_cost_usd" => decimal_to_string(suite_run.avg_cost_usd),
        "avg_latency_ms" => suite_run.avg_latency_ms,
        "total_cost_usd" => decimal_to_string(suite_run.total_cost_usd),
        "cost_sample_count" => suite_run.cost_sample_count,
        "total_latency_ms" => suite_run.total_latency_ms,
        "latency_sample_count" => suite_run.latency_sample_count
      },
      results: Enum.map(suite_run.results, &normalize_result/1)
    }
  end

  @doc "Returns the report as a JSON-compatible map with string keys."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = report) do
    %{
      "type" => report.type,
      "schema_version" => report.schema_version,
      "status" => report.status,
      "suite_run_id" => report.suite_run_id,
      "suite_id" => report.suite_id,
      "prompt_version_id" => report.prompt_version_id,
      "provider_id" => report.provider_id,
      "quality_policy" => report.quality_policy,
      "summary" => report.summary,
      "results" => report.results
    }
  end

  defp evaluation_status(
         %{quality_policy_result: %{"status" => status}},
         _total
       )
       when status in @statuses do
    status
  end

  defp evaluation_status(suite_run, total) do
    if suite_run.failed == 0 and total > 0, do: "passed", else: "failed"
  end

  defp normalize_result(result) do
    %{
      "test_case_id" => result["test_case_id"],
      "test_case_metadata" => result["test_case_metadata"],
      "status" => if(result["passed"], do: "passed", else: "failed"),
      "passed" => result["passed"],
      "score" => result["score"],
      "output" => result["output"],
      "assertion_results" => Map.get(result, "assertion_results", []),
      "input_tokens" => result["input_tokens"],
      "output_tokens" => result["output_tokens"],
      "cost_usd" => result["cost_usd"],
      "latency_ms" => result["latency_ms"]
    }
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
end
