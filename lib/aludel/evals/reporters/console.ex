defmodule Aludel.Evals.Reporters.Console do
  @moduledoc """
  Renders a concise, plain-text evaluation summary.

  The output contains no ANSI sequences, which keeps it readable in local
  terminals and portable across CI log collectors.
  """

  @behaviour Aludel.Evals.Reporter

  alias Aludel.Evals.Report

  @impl true
  def render(%Report{} = report, _options) do
    lines = [
      "Aludel evaluation #{String.upcase(report.status)}",
      "Suite run: #{report.suite_run_id}",
      summary_line(report.summary),
      metric_line(report.summary),
      result_lines(report.results),
      policy_lines(report.quality_policy)
    ]

    {:ok, lines |> List.flatten() |> Enum.reject(&is_nil/1) |> Enum.join("\n")}
  end

  defp summary_line(summary) do
    "Summary: #{summary["passed"]} passed, #{summary["failed"]} failed, " <>
      "#{summary["pass_rate"]}% pass rate"
  end

  defp metric_line(summary) do
    metrics =
      [
        optional_metric("score", summary["avg_score"]),
        optional_metric("cost", summary["avg_cost_usd"], " USD"),
        optional_metric("latency", summary["avg_latency_ms"], " ms")
      ]
      |> Enum.reject(&is_nil/1)

    if metrics == [], do: nil, else: "Averages: #{Enum.join(metrics, ", ")}"
  end

  defp optional_metric(name, value, suffix \\ "")

  defp optional_metric(_name, nil, _suffix) do
    nil
  end

  defp optional_metric(name, value, suffix) do
    "#{name}=#{value}#{suffix}"
  end

  defp result_lines(results) do
    Enum.map(results, fn result ->
      marker = if result["passed"], do: "PASS", else: "FAIL"
      "[#{marker}] test case #{display_id(result["test_case_id"])}"
    end)
  end

  defp policy_lines(nil) do
    []
  end

  defp policy_lines(policy) do
    ["Policy: #{policy["status"]}" | Enum.map(policy["rules"] || [], &policy_rule_line/1)]
  end

  defp policy_rule_line(rule) do
    "  [#{String.upcase(to_string(rule["status"]))}] #{display_id(rule["id"])}: " <>
      display_text(rule["reason"])
  end

  defp display_id(nil) do
    "unknown"
  end

  defp display_id(value) do
    display_text(value)
  end

  defp display_text(nil) do
    ""
  end

  defp display_text(value) do
    value
    |> to_string()
    |> String.replace(~r/[\x00-\x1F\x7F]/u, " ")
    |> String.trim()
  end
end
