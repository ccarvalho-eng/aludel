defmodule Aludel.Evals.SuitePolicyTest do
  use Aludel.DataCase, async: true

  import Mox

  alias Aludel.Evals
  alias Aludel.Interfaces.HttpClientMock
  alias Aludel.Prompts

  setup :verify_on_exit!

  describe "create_suite_policy/2" do
    test "creates immutable policy versions in suite order" do
      suite = suite_fixture()

      assert {:ok, first} = Evals.create_suite_policy(suite, pass_rate_policy(0.5))
      assert first.suite_id == suite.id
      assert first.version == 1

      assert {:ok, second} = Evals.create_suite_policy(suite, pass_rate_policy(0.9))
      assert second.version == 2

      assert Enum.map(Evals.list_suite_policies(suite), & &1.version) == [2, 1]
      assert Evals.latest_suite_policy(suite).id == second.id
    end

    test "rejects invalid policy definitions before persistence" do
      suite = suite_fixture()

      assert {:error, changeset} =
               Evals.create_suite_policy(suite, %{"schema_version" => 2, "rules" => []})

      assert "is invalid" in errors_on(changeset).definition
      assert Evals.list_suite_policies(suite) == []
    end
  end

  describe "suite execution" do
    test "snapshots the latest policy and persists its evaluation" do
      prompt = prompt_fixture()
      {:ok, version} = Prompts.create_prompt_version(prompt, "Answer for {{name}}")
      suite = suite_fixture(%{prompt_id: prompt.id})
      provider = provider_fixture(%{model: "policy-model"})

      passing_case =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"name" => "pass"},
          metadata: %{"priority" => "high"},
          assertions: [%{"type" => "contains", "value" => "accepted"}]
        })

      failing_case =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"name" => "fail"},
          metadata: %{"priority" => "low"},
          assertions: [%{"type" => "contains", "value" => "accepted"}]
        })

      expect(HttpClientMock, :request, 2, fn _model, rendered_prompt, _opts ->
        output =
          if rendered_prompt =~ "pass" do
            "accepted"
          else
            "rejected"
          end

        {:ok, %{content: output, input_tokens: 10, output_tokens: 2}}
      end)

      definition = %{
        "schema_version" => 1,
        "rules" => [
          %{"id" => "overall", "type" => "overall_pass_rate", "minimum" => 0.5},
          %{
            "id" => "priority",
            "type" => "metadata_pass_rate",
            "metadata" => %{"priority" => "high"},
            "minimum" => 1.0
          }
        ]
      }

      assert {:ok, policy} = Evals.create_suite_policy(suite, definition)
      assert {:ok, suite_run} = Evals.execute_suite(suite, version, provider)

      assert suite_run.suite_policy_id == policy.id
      assert suite_run.quality_policy_result["status"] == "passed"
      assert suite_run.quality_policy_result["policy_version"] == 1
      assert suite_run.quality_policy_result["policy_id"] == policy.id

      results_by_id = Map.new(suite_run.results, &{&1["test_case_id"], &1})

      assert results_by_id[passing_case.id]["test_case_metadata"] == %{"priority" => "high"}
      assert results_by_id[failing_case.id]["test_case_metadata"] == %{"priority" => "low"}
    end

    test "retry evaluates the immutable policy snapshot instead of the latest policy" do
      prompt = prompt_fixture()
      {:ok, version} = Prompts.create_prompt_version(prompt, "Answer for {{name}}")
      suite = suite_fixture(%{prompt_id: prompt.id})
      provider = provider_fixture(%{model: "policy-retry-model"})

      passing_case =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"name" => "pass"},
          assertions: [%{"type" => "contains", "value" => "accepted"}]
        })

      failing_case =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"name" => "fail"},
          assertions: [%{"type" => "contains", "value" => "accepted"}]
        })

      expect(HttpClientMock, :request, 2, fn _model, rendered_prompt, _opts ->
        output = if rendered_prompt =~ "pass", do: "accepted", else: "rejected"
        {:ok, %{content: output, input_tokens: 10, output_tokens: 2}}
      end)

      assert {:ok, first_policy} = Evals.create_suite_policy(suite, pass_rate_policy(0.5))
      assert {:ok, suite_run} = Evals.execute_suite(suite, version, provider)
      assert suite_run.quality_policy_result["status"] == "passed"

      assert {:ok, latest_policy} = Evals.create_suite_policy(suite, pass_rate_policy(1.0))
      assert latest_policy.version == 2

      expect(HttpClientMock, :request, fn _model, _messages, _opts ->
        {:ok, %{content: "rejected", input_tokens: 10, output_tokens: 2}}
      end)

      assert {:ok, retried_run} =
               Evals.retry_suite_run_test_case(suite_run, failing_case.id)

      assert retried_run.suite_policy_id == first_policy.id
      assert retried_run.quality_policy_result["policy_version"] == 1
      assert retried_run.quality_policy_result["status"] == "passed"
      assert retried_run.quality_policy_result["rules"] |> hd() |> Map.fetch!("actual") == 0.5
      assert Enum.any?(retried_run.results, &(&1["test_case_id"] == passing_case.id))
    end

    test "leaves legacy runs without a policy result" do
      prompt = prompt_fixture()
      {:ok, version} = Prompts.create_prompt_version(prompt, "Answer")
      suite = suite_fixture(%{prompt_id: prompt.id})
      provider = provider_fixture(%{model: "no-policy-model"})

      assert {:ok, suite_run} = Evals.execute_suite(suite, version, provider)
      assert is_nil(suite_run.suite_policy_id)
      assert is_nil(suite_run.quality_policy_result)
    end
  end

  defp pass_rate_policy(minimum) do
    %{
      "schema_version" => 1,
      "rules" => [
        %{"id" => "overall", "type" => "overall_pass_rate", "minimum" => minimum}
      ]
    }
  end
end
