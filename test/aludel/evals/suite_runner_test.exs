defmodule Aludel.Evals.SuiteRunnerTest do
  use Aludel.DataCase

  import Mox

  alias Aludel.Evals.SuiteRunner

  setup :set_mox_global
  setup :verify_on_exit!

  describe "execute/3 and execute/4" do
    test "returns a persisted suite run" do
      prompt = prompt_fixture_with_version(%{template: "Hello {{name}}"})
      suite = suite_fixture(%{prompt_id: prompt.id})
      provider = provider_fixture()
      version = List.first(prompt.versions)

      assert {:ok, suite_run} = SuiteRunner.execute(suite.id, version.id, provider.id)
      assert suite_run.suite_id == suite.id
      assert suite_run.prompt_version_id == version.id
      assert suite_run.provider_id == provider.id
    end

    test "returns a structured error when dependent records cannot be loaded" do
      prompt = prompt_fixture_with_version(%{template: "Hello {{name}}"})
      suite = suite_fixture(%{prompt_id: prompt.id})
      provider = provider_fixture()
      version = List.first(prompt.versions)

      assert {:error, :suite_not_found} =
               SuiteRunner.execute(Ecto.UUID.generate(), version.id, provider.id)

      assert {:error, :prompt_version_not_found} =
               SuiteRunner.execute(suite.id, Ecto.UUID.generate(), provider.id)

      assert {:error, :provider_not_found} =
               SuiteRunner.execute(suite.id, version.id, Ecto.UUID.generate())
    end

    test "forwards sampling validation errors" do
      prompt = prompt_fixture_with_version(%{template: "Hello {{name}}"})
      suite = suite_fixture(%{prompt_id: prompt.id})
      provider = provider_fixture()
      version = List.first(prompt.versions)

      assert {:error, {:invalid_sampling, _message}} =
               SuiteRunner.execute(suite.id, version.id, provider.id, samples: 21)
    end

    test "executes suites through the configured callback executor" do
      original_mode = Application.get_env(:aludel, :execution_mode)
      original_executor = Application.get_env(:aludel, :executor)

      Application.put_env(:aludel, :execution_mode, :callback)
      Application.put_env(:aludel, :executor, Aludel.ExecutorMock)

      on_exit(fn ->
        Application.put_env(:aludel, :execution_mode, original_mode)
        Application.put_env(:aludel, :executor, original_executor)
      end)

      prompt = prompt_fixture_with_version(%{template: "Hello {{name}}"})
      suite = suite_fixture(%{prompt_id: prompt.id})
      provider = provider_fixture(%{provider: :openai, model: "callback-suite-model"})
      version = List.first(prompt.versions)

      test_case =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"name" => "Alice"},
          assertions: [%{"type" => "contains", "value" => "reset password"}]
        })

      _document =
        test_case_document_fixture(%{
          test_case_id: test_case.id,
          filename: "policy.txt",
          content_type: "text/plain",
          data: "reset password instructions"
        })

      expect(Aludel.ExecutorMock, :run, fn input ->
        assert input.kind == :suite
        assert input.variables == %{"name" => "Alice"}
        assert input.provider.id == provider.id
        assert input.metadata.suite_id == suite.id
        assert input.metadata.test_case_id == test_case.id
        assert [%{name: "policy.txt", content_type: "text/plain", data: data}] = input.documents
        assert data == "reset password instructions"

        {:ok,
         %{
           output: "Use the reset password flow.",
           input_tokens: nil,
           output_tokens: 9,
           latency_ms: 222,
           cost_usd: nil,
           metadata: %{"trace_id" => "suite-trace-1"}
         }}
      end)

      assert {:ok, suite_run} = SuiteRunner.execute(suite.id, version.id, provider.id)

      assert suite_run.suite_id == suite.id
      assert suite_run.provider_id == provider.id
      assert suite_run.passed == 1
      assert suite_run.failed == 0
      assert suite_run.avg_latency_ms == 222
      assert suite_run.avg_cost_usd == nil

      assert [
               %{
                 "output" => "Use the reset password flow.",
                 "input_tokens" => nil,
                 "output_tokens" => 9,
                 "latency_ms" => 222,
                 "cost_usd" => nil,
                 "metadata" => %{"trace_id" => "suite-trace-1"}
               }
             ] = suite_run.results
    end

    test "stores failed suite results when the callback executor crashes" do
      original_mode = Application.get_env(:aludel, :execution_mode)
      original_executor = Application.get_env(:aludel, :executor)

      Application.put_env(:aludel, :execution_mode, :callback)
      Application.put_env(:aludel, :executor, Aludel.ExecutorMock)

      on_exit(fn ->
        Application.put_env(:aludel, :execution_mode, original_mode)
        Application.put_env(:aludel, :executor, original_executor)
      end)

      prompt = prompt_fixture_with_version(%{template: "Hello {{name}}"})
      suite = suite_fixture(%{prompt_id: prompt.id})
      provider = provider_fixture(%{provider: :openai, model: "callback-suite-model"})
      version = List.first(prompt.versions)

      test_case =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"name" => "Alice"},
          assertions: [%{"type" => "contains", "value" => "reset password"}]
        })

      expect(Aludel.ExecutorMock, :run, fn _input ->
        raise "boom"
      end)

      assert {:ok, suite_run} = SuiteRunner.execute(suite.id, version.id, provider.id)
      assert suite_run.passed == 0
      assert suite_run.failed == 1
      assert suite_run.avg_latency_ms == nil
      assert suite_run.avg_cost_usd == nil

      assert [
               %{
                 "passed" => false,
                 "output" => output,
                 "latency_ms" => nil,
                 "cost_usd" => nil
               }
             ] = suite_run.results

      assert output =~ "executor_crash"
      assert output =~ "boom"
      assert test_case.id in Enum.map(suite_run.results, & &1["test_case_id"])
    end
  end

  describe "launch/4" do
    test "sends the suite completion result to the recipient" do
      prompt = prompt_fixture_with_version(%{template: "Hello {{name}}"})
      suite = suite_fixture(%{prompt_id: prompt.id})
      provider = provider_fixture()
      version = List.first(prompt.versions)

      assert {:ok, task_pid} = SuiteRunner.launch(self(), suite.id, version.id, provider.id)
      monitor_ref = Process.monitor(task_pid)

      assert_receive {:suite_completed, {:ok, suite_run}}, 1000
      assert suite_run.suite_id == suite.id
      assert_receive {:DOWN, ^monitor_ref, :process, ^task_pid, :normal}, 1000
    end

    test "sends an error result when dependent records cannot be loaded" do
      prompt = prompt_fixture_with_version(%{template: "Hello {{name}}"})
      suite = suite_fixture(%{prompt_id: prompt.id})
      version = List.first(prompt.versions)

      assert {:ok, task_pid} =
               SuiteRunner.launch(self(), suite.id, version.id, Ecto.UUID.generate())

      monitor_ref = Process.monitor(task_pid)

      assert_receive {:suite_completed, {:error, :provider_not_found}}, 1000
      assert_receive {:DOWN, ^monitor_ref, :process, ^task_pid, :normal}, 1000
    end
  end
end
