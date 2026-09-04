defmodule Aludel.ExUnit do
  @moduledoc """
  Adds evaluation assertions to ExUnit tests.

  Use `assert_evaluation/2` for one generated response, or
  `assert_evaluations/2` when the same response must satisfy several metrics.
  Persisted suite runs can be checked with `assert_suite_run/1`.
  `assert_suite/3` or `assert_suite/4` executes and persists a suite before
  applying the same gate.

  Failure messages identify the metric, failed test case, or quality-policy
  rule without copying generated model output into test logs.

  ## Usage

      defmodule MyApp.AnswerTest do
        use ExUnit.Case
        use Aludel.ExUnit

        test "answers with the expected city" do
          output = MyApp.answer("What is the capital of France?")

          assert_evaluation(output, %{
            "type" => "exact_match",
            "value" => "Paris"
          })
        end
      end

  The helpers can also be called as qualified functions without `use`.
  """

  alias Aludel.Evals
  alias Aludel.Evals.AssertionEvaluator
  alias Aludel.Evals.Metric.Context
  alias Aludel.Evals.Report
  alias Aludel.Evals.Suite
  alias Aludel.Evals.SuiteRun
  alias Aludel.Prompts.PromptVersion
  alias Aludel.Providers.Provider

  @max_failure_items 20
  @max_text_characters 1_000

  @typedoc "An assertion accepted by `Aludel.Evals.AssertionEvaluator`."
  @type evaluation_assertion :: map()

  @doc false
  defmacro __using__(_options) do
    quote do
      import Aludel.ExUnit,
        only: [
          assert_evaluation: 2,
          assert_evaluations: 2,
          assert_suite: 3,
          assert_suite: 4,
          assert_suite_run: 1
        ]
    end
  end

  @doc """
  Evaluates one assertion and returns its normalized result when it passes.

  The input can be generated output text or an `Aludel.Evals.Metric.Context`.
  A failed, invalid, unsupported, or unavailable evaluator raises
  `ExUnit.AssertionError` with bounded diagnostic evidence. Generated output
  and expected values are omitted from the failure message.
  """
  @spec assert_evaluation(Context.t() | String.t(), evaluation_assertion()) :: map()
  def assert_evaluation(input, assertion) when is_map(assertion) do
    result = AssertionEvaluator.evaluate(input, assertion)

    if result["passed"] do
      result
    else
      fail_assertion(evaluation_failure_message(result))
    end
  end

  @doc """
  Evaluates a non-empty list of assertions and returns the ordered results.

  All assertions run so one failure reports every non-passing metric, up to a
  bounded diagnostic limit. Raises `ExUnit.AssertionError` when the list is
  empty or any assertion does not pass.
  """
  @spec assert_evaluations(Context.t() | String.t(), [evaluation_assertion()]) :: [map()]
  def assert_evaluations(_input, []) do
    fail_assertion("Evaluation requires at least one assertion")
  end

  def assert_evaluations(input, assertions) when is_list(assertions) do
    results = Enum.map(assertions, &AssertionEvaluator.evaluate(input, &1))

    failures =
      results
      |> Enum.with_index(1)
      |> Enum.reject(fn {result, _index} -> result["passed"] end)

    if failures == [] do
      results
    else
      fail_assertion(evaluations_failure_message(results, failures))
    end
  end

  @doc """
  Requires an existing persisted suite run to have an effective passing status.

  A stored quality-policy result determines the effective status when present.
  Otherwise, every test case must pass and an empty run fails. The passing run
  is returned unchanged so callers can make additional assertions about it.
  """
  @spec assert_suite_run(SuiteRun.t()) :: SuiteRun.t()
  def assert_suite_run(%SuiteRun{} = suite_run) do
    report = Report.from_suite_run(suite_run)

    if report.status == "passed" do
      suite_run
    else
      fail_assertion(suite_failure_message(report))
    end
  end

  @doc """
  Executes, persists, and gates an evaluation suite from an ExUnit test.

  Sampling options are forwarded to `Aludel.Evals.execute_suite/4`. A completed
  non-passing run remains persisted before this helper raises. Configuration or
  execution errors raise with a stable error category.
  """
  @spec assert_suite(Suite.t(), PromptVersion.t(), Provider.t(), keyword()) :: SuiteRun.t()
  def assert_suite(suite, prompt_version, provider, options \\ [])

  def assert_suite(
        %Suite{} = suite,
        %PromptVersion{} = prompt_version,
        %Provider{} = provider,
        options
      )
      when is_list(options) do
    with :ok <- validate_prompt_version(suite, prompt_version),
         {:ok, suite_run} <- execute_suite(suite, prompt_version, provider, options) do
      assert_suite_run(suite_run)
    else
      {:error, reason} ->
        fail_assertion("Evaluation suite could not run: #{execution_error_category(reason)}")
    end
  end

  defp validate_prompt_version(suite, prompt_version) do
    if suite.prompt_id == prompt_version.prompt_id do
      :ok
    else
      {:error, :prompt_version_mismatch}
    end
  end

  defp execute_suite(suite, prompt_version, provider, options) do
    Evals.execute_suite(suite, prompt_version, provider, options)
  rescue
    _error ->
      {:error, :execution_failed}
  catch
    _kind, _reason ->
      {:error, :execution_failed}
  end

  defp evaluation_failure_message(result) do
    [
      "Evaluation assertion failed",
      "Metric: #{display_text(result["type"], "unknown")}",
      "Score: #{display_text(result["score"], "unavailable")}",
      "Evaluator: #{evaluator_status(result)}",
      "Reason: #{display_text(result["reason"], "Assertion did not pass")}"
    ]
    |> Enum.join("\n")
  end

  defp evaluations_failure_message(results, failures) do
    failure_lines =
      failures
      |> Enum.take(@max_failure_items)
      |> Enum.map(fn {failure, index} ->
        "[#{index}] #{display_text(failure["type"], "unknown")} " <>
          "(score #{display_text(failure["score"], "unavailable")}, " <>
          "evaluator #{evaluator_status(failure)}): " <>
          display_text(failure["reason"], "Assertion did not pass")
      end)

    omitted_count = length(failures) - length(failure_lines)

    [
      "#{length(failures)} of #{length(results)} evaluation assertions failed",
      failure_lines,
      omitted_line(omitted_count)
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp suite_failure_message(report) do
    failed_cases =
      report.results
      |> Enum.reject(& &1["passed"])
      |> Enum.flat_map(&failed_case_lines/1)

    all_details = failed_cases ++ policy_failure_lines(report.quality_policy)
    details = Enum.take(all_details, @max_failure_items)
    omitted_count = length(all_details) - length(details)

    [
      "Evaluation suite did not pass",
      "Status: #{report.status}",
      "Suite run: #{display_text(report.suite_run_id, "unknown")}",
      suite_summary(report.summary),
      empty_run_line(report.summary),
      details,
      omitted_line(omitted_count)
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp failed_case_lines(result) do
    failures =
      result
      |> Map.get("assertion_results", [])
      |> Enum.reject(& &1["passed"])

    case failures do
      [] ->
        ["Test case #{display_text(result["test_case_id"], "unknown")}: Evaluation failed"]

      failures ->
        Enum.map(failures, fn failure ->
          "Test case #{display_text(result["test_case_id"], "unknown")}: " <>
            "#{display_text(failure["type"], "assertion")} - " <>
            display_text(failure["reason"], "Assertion did not pass")
        end)
    end
  end

  defp policy_failure_lines(nil) do
    []
  end

  defp policy_failure_lines(policy) do
    policy
    |> Map.get("rules", [])
    |> Enum.reject(&(&1["status"] == "passed"))
    |> Enum.map(fn rule ->
      "Policy #{display_text(rule["id"], "rule")} " <>
        "[#{display_text(rule["status"], "unknown")}]: " <>
        display_text(rule["reason"], "Quality policy rule did not pass")
    end)
  end

  defp suite_summary(summary) do
    "Summary: #{summary["passed"]} passed, #{summary["failed"]} failed, " <>
      "#{summary["pass_rate"]}% pass rate"
  end

  defp empty_run_line(%{"total" => 0}) do
    "No evaluation cases were available"
  end

  defp empty_run_line(_summary) do
    nil
  end

  defp evaluator_status(%{"evaluator" => %{"status" => status}}) do
    display_text(status, "unavailable")
  end

  defp evaluator_status(_result) do
    "unavailable"
  end

  defp execution_error_category(reason) when is_atom(reason) do
    Atom.to_string(reason)
  end

  defp execution_error_category(reason) when is_tuple(reason) and tuple_size(reason) > 0 do
    reason
    |> elem(0)
    |> execution_error_category()
  end

  defp execution_error_category(_reason) do
    "execution_failed"
  end

  defp omitted_line(count) when count > 0 do
    "... and #{count} more failures"
  end

  defp omitted_line(_count) do
    nil
  end

  defp display_text(nil, fallback) do
    fallback
  end

  defp display_text(value, fallback) do
    value
    |> to_string()
    |> String.replace(~r/[\x00-\x1F\x7F]/u, " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.slice(0, @max_text_characters)
    |> case do
      "" -> fallback
      text -> text
    end
  end

  defp fail_assertion(message) do
    raise ExUnit.AssertionError, message: message
  end
end
