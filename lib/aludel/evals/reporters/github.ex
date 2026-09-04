defmodule Aludel.Evals.Reporters.GitHub do
  @moduledoc """
  Renders GitHub Actions workflow-command annotations.

  Failed test cases and non-passing policy rules become error annotations. A
  passing run emits one notice. Untrusted result text is escaped and bounded so
  it cannot create additional workflow commands or unbounded log records.
  """

  @behaviour Aludel.Evals.Reporter

  alias Aludel.Evals.Report

  @max_message_characters 4_096

  @impl true
  def render(%Report{status: "passed"} = report, _options) do
    {:ok,
     annotation(
       "notice",
       "Aludel evaluation",
       "Suite run #{report.suite_run_id} passed"
     )}
  end

  def render(%Report{} = report, _options) do
    annotations =
      report.results
      |> Enum.reject(& &1["passed"])
      |> Enum.map(&failed_test_annotation/1)
      |> Kernel.++(policy_annotations(report.quality_policy))
      |> ensure_failure_annotation(report)

    {:ok, Enum.intersperse(annotations, "\n")}
  end

  defp failed_test_annotation(result) do
    reasons =
      result
      |> Map.get("assertion_results", [])
      |> Enum.reject(& &1["passed"])
      |> Enum.map_join("; ", &(&1["reason"] || "Assertion failed"))

    message = if reasons == "", do: "Evaluation failed", else: reasons
    annotation("error", "Test case #{result["test_case_id"] || "unknown"}", message)
  end

  defp policy_annotations(nil) do
    []
  end

  defp policy_annotations(policy) do
    policy
    |> Map.get("rules", [])
    |> Enum.reject(&(&1["status"] == "passed"))
    |> Enum.map(fn rule ->
      annotation(
        "error",
        "Quality policy #{rule["id"] || "rule"}",
        rule["reason"] || "Quality policy rule did not pass"
      )
    end)
  end

  defp ensure_failure_annotation([], report) do
    [annotation("error", "Aludel evaluation", "Suite run #{report.suite_run_id} did not pass")]
  end

  defp ensure_failure_annotation(annotations, _report) do
    annotations
  end

  defp annotation(level, title, message) do
    "::#{level} title=#{escape_property(title)}::#{escape_message(message)}"
  end

  defp escape_property(value) do
    value
    |> bounded_string()
    |> escape_common()
    |> String.replace(":", "%3A")
    |> String.replace(",", "%2C")
  end

  defp escape_message(value) do
    value
    |> bounded_string()
    |> escape_common()
  end

  defp escape_common(value) do
    value
    |> String.replace("%", "%25")
    |> String.replace("\r", "%0D")
    |> String.replace("\n", "%0A")
  end

  defp bounded_string(value) do
    value
    |> to_string()
    |> String.slice(0, @max_message_characters)
  end
end
