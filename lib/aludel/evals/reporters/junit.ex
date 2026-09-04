defmodule Aludel.Evals.Reporters.JUnit do
  @moduledoc """
  Renders evaluation results as JUnit XML for CI test-report viewers.

  Each evaluation case becomes a `<testcase>`. Failed cases contain a
  `<failure>` element with their failed assertion reasons. Generated model
  output is omitted by default and can be included as escaped `<system-out>`
  text with `include_output: true`.
  """

  @behaviour Aludel.Evals.Reporter

  alias Aludel.Evals.Report

  @impl true
  def render(%Report{} = report, options) do
    suite_name = "Aludel suite #{report.suite_id}"

    total_seconds = total_seconds(report.summary, length(report.results))

    synthetic_failure_count = synthetic_failure_count(report)
    test_count = length(report.results) + synthetic_failure_count
    failure_count = Enum.count(report.results, &(not &1["passed"])) + synthetic_failure_count

    document = [
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      ~s(<testsuites tests="#{test_count}" failures="#{failure_count}" errors="0" time="#{total_seconds}">\n),
      ~s(  <testsuite name="#{xml(suite_name)}" tests="#{test_count}" failures="#{failure_count}" errors="0" time="#{total_seconds}">\n),
      properties(report),
      Enum.map(report.results, &test_case(report, &1, options)),
      synthetic_test_case(report),
      "  </testsuite>\n",
      "</testsuites>\n"
    ]

    {:ok, document}
  end

  defp properties(report) do
    [
      "    <properties>\n",
      property("schema_version", report.schema_version),
      property("suite_run_id", report.suite_run_id),
      property("status", report.status),
      "    </properties>\n"
    ]
  end

  defp property(name, value) do
    ~s(      <property name="#{xml(name)}" value="#{xml(value)}"/>\n)
  end

  defp test_case(report, result, options) do
    latency = milliseconds_to_seconds(result["latency_ms"], 1)
    test_case_id = result["test_case_id"] || "unknown"

    [
      ~s(    <testcase name="#{xml(test_case_id)}" classname="aludel.suite.#{xml(report.suite_id)}" time="#{latency}">\n),
      failure(result),
      system_out(result["output"], Keyword.get(options, :include_output, false)),
      "    </testcase>\n"
    ]
  end

  defp failure(%{"passed" => true}) do
    []
  end

  defp failure(result) do
    message = failure_message(result)

    ~s(      <failure message="Evaluation assertions failed" type="evaluation_failure">#{xml(message)}</failure>\n)
  end

  defp failure_message(result) do
    result
    |> Map.get("assertion_results", [])
    |> Enum.reject(& &1["passed"])
    |> Enum.map_join("; ", &(&1["reason"] || "Assertion failed"))
    |> case do
      "" -> "Evaluation failed"
      message -> message
    end
  end

  defp system_out(_output, false) do
    []
  end

  defp system_out(nil, true) do
    []
  end

  defp system_out(output, true) do
    ~s(      <system-out>#{xml(output)}</system-out>\n)
  end

  defp synthetic_failure_count(%Report{status: "passed"}) do
    0
  end

  defp synthetic_failure_count(%Report{quality_policy: quality_policy})
       when not is_nil(quality_policy) do
    1
  end

  defp synthetic_failure_count(%Report{results: results}) do
    if Enum.any?(results, &(not &1["passed"])), do: 0, else: 1
  end

  defp synthetic_test_case(%Report{status: "passed"}) do
    []
  end

  defp synthetic_test_case(%Report{quality_policy: quality_policy} = report)
       when not is_nil(quality_policy) do
    message =
      report.quality_policy
      |> Map.get("rules", [])
      |> Enum.reject(&(&1["status"] == "passed"))
      |> Enum.map_join("; ", &(&1["reason"] || "Quality policy rule did not pass"))
      |> case do
        "" -> "Quality policy did not pass"
        reasons -> reasons
      end

    [
      ~s(    <testcase name="quality-policy" classname="aludel.suite.#{xml(report.suite_id)}" time="0">\n),
      ~s(      <failure message="Quality policy did not pass" type="quality_policy_failure">#{xml(message)}</failure>\n),
      "    </testcase>\n"
    ]
  end

  defp synthetic_test_case(%Report{} = report) do
    if Enum.any?(report.results, &(not &1["passed"])) do
      []
    else
      [
        ~s(    <testcase name="evaluation" classname="aludel.suite.#{xml(report.suite_id)}" time="0">\n),
        ~s(      <failure message="Evaluation did not pass" type="evaluation_failure">No evaluation cases were available</failure>\n),
        "    </testcase>\n"
      ]
    end
  end

  defp milliseconds_to_seconds(nil, _multiplier) do
    "0"
  end

  defp milliseconds_to_seconds(milliseconds, multiplier) do
    milliseconds
    |> Kernel.*(multiplier)
    |> Kernel./(1000)
    |> :erlang.float_to_binary(decimals: 3)
  end

  defp total_seconds(%{"total_latency_ms" => total_latency_ms}, _result_count)
       when is_integer(total_latency_ms) do
    milliseconds_to_seconds(total_latency_ms, 1)
  end

  defp total_seconds(summary, result_count) do
    milliseconds_to_seconds(summary["avg_latency_ms"], result_count)
  end

  defp xml(value) do
    value
    |> to_string()
    |> String.replace(~r/[^\x09\x0A\x0D\x20-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]/u, "")
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
