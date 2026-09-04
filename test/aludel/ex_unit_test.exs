defmodule Aludel.ExUnitTest do
  use Aludel.DataCase
  use Aludel.ExUnit

  import Mox

  alias Aludel.Evals
  alias Aludel.Evals.Metric.Context
  alias Aludel.Evals.SuiteRun
  alias Aludel.Interfaces.HttpClientMock

  setup :set_mox_from_context
  setup :verify_on_exit!

  describe "assert_evaluation/2" do
    test "returns the normalized result when the assertion passes" do
      result =
        assert_evaluation("Paris", %{
          "type" => "exact_match",
          "value" => "Paris"
        })

      assert result["passed"]
      assert result["type"] == "exact_match"
      assert result["score"] == 100.0
    end

    test "accepts contextual metric input" do
      context =
        Context.new("Paris",
          expected: "Paris",
          rendered_input: "What is the capital of France?"
        )

      result =
        assert_evaluation(context, %{
          "type" => "contains",
          "value" => "Paris"
        })

      assert result["passed"]
    end

    test "raises a concise assertion error without including generated output" do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_evaluation("private generated response", %{
            "type" => "exact_match",
            "value" => "expected response"
          })
        end

      assert error.message =~ "Evaluation assertion failed"
      assert error.message =~ "Metric: exact_match"
      assert error.message =~ "Score: 0.0"
      refute error.message =~ "private generated response"
      refute error.message =~ "expected response"
    end

    test "reports unsupported assertion types as evaluation failures" do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_evaluation("response", %{"type" => "missing_metric"})
        end

      assert error.message =~ "Metric: missing_metric"
      assert error.message =~ "Evaluator: unavailable"
      assert error.message =~ "Unsupported metric type"
    end
  end

  describe "assert_evaluations/2" do
    test "returns ordered results when every assertion passes" do
      results =
        assert_evaluations("Paris, France", [
          %{"type" => "contains", "value" => "Paris"},
          %{"type" => "not_contains", "value" => "London"}
        ])

      assert Enum.map(results, & &1["type"]) == ["contains", "not_contains"]
    end

    test "reports every failed assertion with bounded, sanitized reasons" do
      long_reason = String.duplicate("x", 3_000) <> "\nsecond line"

      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_evaluations("output", [
            %{"type" => "exact_match", "value" => "different"},
            %{"type" => "missing_metric", "value" => long_reason}
          ])
        end

      assert error.message =~ "2 of 2 evaluation assertions failed"
      assert error.message =~ "[1] exact_match"
      assert error.message =~ "[2] missing_metric"
      refute error.message =~ "\nsecond line"
      assert String.length(error.message) < 2_500
    end

    test "rejects an empty assertion list" do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_evaluations("output", [])
        end

      assert error.message == "Evaluation requires at least one assertion"
    end
  end

  describe "assert_suite_run/1" do
    test "returns a suite run when its effective quality status passes" do
      suite_run =
        suite_run(%{
          passed: 0,
          failed: 1,
          quality_policy_result: %{"status" => "passed", "rules" => []}
        })

      assert assert_suite_run(suite_run) == suite_run
    end

    test "raises with failed cases and policy evidence but no generated output" do
      policy_reason =
        "Cost exceeded\rthe configured limit " <>
          String.duplicate("detail ", 300) <> "\nprivate trailing detail"

      suite_run =
        suite_run(%{
          quality_policy_result: %{
            "status" => "failed",
            "rules" => [
              %{
                "id" => "cost\nlimit",
                "status" => "failed",
                "reason" => policy_reason
              }
            ]
          }
        })

      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_suite_run(suite_run)
        end

      assert error.message =~ "Evaluation suite did not pass"
      assert error.message =~ "Status: failed"
      assert error.message =~ "Summary: 0 passed, 1 failed"
      assert error.message =~ "Test case case-fail: exact_match"
      assert error.message =~ "Policy cost limit [failed]: Cost exceeded the configured limit"
      refute error.message =~ "private generated response"
      refute error.message =~ "private trailing detail"
      assert String.length(error.message) < 1_500
    end

    test "treats an empty policy-free run as a failure" do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_suite_run(suite_run(%{passed: 0, failed: 0, results: []}))
        end

      assert error.message =~ "No evaluation cases were available"
    end
  end

  describe "assert_suite/3 and assert_suite/4" do
    test "executes, persists, and returns a passing suite run" do
      stub(HttpClientMock, :request, fn _model, _prompt, _options ->
        eval_response("Paris")
      end)

      {suite, version, provider} = executable_suite("Paris")

      suite_run = assert_suite(suite, version, provider)

      assert suite_run.passed == 1
      assert Evals.get_suite_run!(suite_run.id).id == suite_run.id
    end

    test "persists a failed run before raising the quality-gate assertion" do
      stub(HttpClientMock, :request, fn _model, _prompt, _options ->
        eval_response("London")
      end)

      {suite, version, provider} = executable_suite("Paris")

      assert_raise ExUnit.AssertionError, ~r/Evaluation suite did not pass/, fn ->
        assert_suite(suite, version, provider)
      end

      assert [%SuiteRun{failed: 1}] = Evals.list_suite_runs()
    end

    test "turns pre-execution configuration errors into assertion failures" do
      {suite, version, provider} = executable_suite("Paris")

      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_suite(suite, version, provider, samples: 0)
        end

      assert error.message == "Evaluation suite could not run: invalid_sampling"
      assert Evals.list_suite_runs() == []
    end

    test "rejects a prompt version from another prompt before execution" do
      {suite, _version, provider} = executable_suite("Paris")
      other_prompt = prompt_fixture()
      {:ok, other_version} = Aludel.Prompts.create_prompt_version(other_prompt, "Other prompt")

      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_suite(suite, other_version, provider)
        end

      assert error.message == "Evaluation suite could not run: prompt_version_mismatch"
      assert Evals.list_suite_runs() == []
    end

    test "does not expose exception details from suite execution" do
      stub(HttpClientMock, :request, fn _model, _prompt, _options ->
        raise "private provider detail"
      end)

      {suite, version, provider} = executable_suite("Paris")

      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_suite(suite, version, provider)
        end

      assert error.message == "Evaluation suite could not run: execution_failed"
      refute error.message =~ "private provider detail"
    end
  end

  defp executable_suite(expected) do
    prompt = prompt_fixture()
    suite = suite_fixture(%{prompt_id: prompt.id})
    {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Answer {{question}}")
    provider = provider_fixture()

    _test_case =
      test_case_fixture(%{
        suite_id: suite.id,
        variable_values: %{"question" => "Capital of France?"},
        assertions: [%{"type" => "exact_match", "value" => expected}]
      })

    {suite, version, provider}
  end

  defp suite_run(overrides) do
    defaults = %{
      id: "run-123",
      suite_id: "suite-123",
      prompt_version_id: "version-123",
      provider_id: "provider-123",
      passed: 0,
      failed: 1,
      avg_score: Decimal.new("0"),
      avg_cost_usd: nil,
      avg_latency_ms: nil,
      total_cost_usd: nil,
      cost_sample_count: 0,
      total_latency_ms: nil,
      latency_sample_count: 0,
      quality_policy_result: nil,
      results: [
        %{
          "test_case_id" => "case-fail",
          "test_case_metadata" => %{},
          "passed" => false,
          "score" => 0.0,
          "output" => "private generated response",
          "assertion_results" => [
            %{
              "type" => "exact_match",
              "passed" => false,
              "score" => 0.0,
              "reason" => "Output did not match exactly",
              "evaluator" => %{"status" => "completed"}
            }
          ]
        }
      ]
    }

    struct!(SuiteRun, Map.merge(defaults, overrides))
  end
end
