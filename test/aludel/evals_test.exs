defmodule Aludel.EvalsTest do
  use Aludel.DataCase

  import Mox
  import Aludel.PromptsFixtures
  import Aludel.ProvidersFixtures

  alias Aludel.Evals
  alias Aludel.Evals.SuiteRun
  alias Aludel.Evals.TestCaseDocument
  alias Aludel.Interfaces.HttpClientMock
  alias Aludel.Interfaces.Storage.Adapters.Local
  alias Aludel.Interfaces.StorageMock

  setup :set_mox_from_context
  setup :verify_on_exit!

  describe "suites" do
    test "create_suite/1 creates a suite with valid attributes" do
      prompt = prompt_fixture()

      attrs = %{
        name: "Test Suite",
        prompt_id: prompt.id
      }

      assert {:ok, suite} = Evals.create_suite(attrs)
      assert suite.name == "Test Suite"
      assert suite.prompt_id == prompt.id
    end

    test "create_suite/1 requires name" do
      prompt = prompt_fixture()

      attrs = %{prompt_id: prompt.id}

      assert {:error, changeset} = Evals.create_suite(attrs)
      assert "can't be blank" in errors_on(changeset).name
    end

    test "create_suite/1 requires prompt_id" do
      attrs = %{name: "Test Suite"}

      assert {:error, changeset} = Evals.create_suite(attrs)
      assert "can't be blank" in errors_on(changeset).prompt_id
    end

    test "list_suites/0 returns all suites" do
      suite = suite_fixture()
      suites = Evals.list_suites()

      assert length(suites) == 1
      assert hd(suites).id == suite.id
    end

    test "get_suite!/1 returns the suite with given id" do
      suite = suite_fixture()
      fetched_suite = Evals.get_suite!(suite.id)

      assert fetched_suite.id == suite.id
      assert fetched_suite.name == suite.name
    end

    test "get_suite_with_test_cases!/1 preloads test cases" do
      suite = suite_fixture()
      _test_case = test_case_fixture(%{suite_id: suite.id})

      fetched_suite = Evals.get_suite_with_test_cases!(suite.id)

      assert fetched_suite.id == suite.id
      refute match?(%Ecto.Association.NotLoaded{}, fetched_suite.test_cases)
      assert length(fetched_suite.test_cases) == 1
    end

    test "update_suite/2 updates the suite" do
      suite = suite_fixture()

      assert {:ok, updated_suite} = Evals.update_suite(suite, %{name: "Updated"})
      assert updated_suite.name == "Updated"
    end

    test "delete_suite/1 deletes the suite" do
      suite = suite_fixture()

      assert {:ok, _suite} = Evals.delete_suite(suite)
      assert_raise Ecto.NoResultsError, fn -> Evals.get_suite!(suite.id) end
    end

    test "change_suite/1 returns a suite changeset" do
      suite = suite_fixture()
      changeset = Evals.change_suite(suite)

      assert %Ecto.Changeset{} = changeset
    end

    test "get_suite_with_test_cases_and_prompt!/1 preloads documents" do
      suite = suite_fixture()
      test_case = test_case_fixture(%{suite_id: suite.id})

      {:ok, _doc} =
        Aludel.Evals.create_test_case_document(%{
          test_case_id: test_case.id,
          filename: "test.pdf",
          content_type: "application/pdf",
          data: <<1, 2, 3>>,
          size_bytes: 3
        })

      loaded = Aludel.Evals.get_suite_with_test_cases_and_prompt!(suite.id)
      assert [test_case] = loaded.test_cases
      assert [%Aludel.Evals.TestCaseDocument{filename: "test.pdf"}] = test_case.documents
    end

    test "list_suites_with_prompt/0 returns suites with prompts preloaded" do
      suite = suite_fixture()
      suites = Evals.list_suites_with_prompt()

      assert length(suites) == 1
      assert hd(suites).id == suite.id
      refute match?(%Ecto.Association.NotLoaded{}, hd(suites).prompt)
    end

    test "get_suite_with_prompt!/1 preloads prompt" do
      suite = suite_fixture()
      loaded = Evals.get_suite_with_prompt!(suite.id)

      assert loaded.id == suite.id
      refute match?(%Ecto.Association.NotLoaded{}, loaded.prompt)
    end
  end

  describe "test_cases" do
    test "create_test_case/1 creates a test case with valid attributes" do
      suite = suite_fixture()

      attrs = %{
        suite_id: suite.id,
        variable_values: %{"name" => "John"},
        assertions: [%{"type" => "contains", "value" => "Hello"}]
      }

      assert {:ok, test_case} = Evals.create_test_case(attrs)
      assert test_case.suite_id == suite.id
      assert test_case.variable_values == %{"name" => "John"}
      assert test_case.assertions == [%{"type" => "contains", "value" => "Hello"}]
    end

    test "create_test_case/1 requires suite_id" do
      attrs = %{
        variable_values: %{},
        assertions: []
      }

      assert {:error, changeset} = Evals.create_test_case(attrs)
      assert "can't be blank" in errors_on(changeset).suite_id
    end

    test "create_test_case/1 requires variable_values" do
      suite = suite_fixture()

      attrs = %{
        suite_id: suite.id,
        assertions: []
      }

      assert {:error, changeset} = Evals.create_test_case(attrs)
      assert "can't be blank" in errors_on(changeset).variable_values
    end

    test "create_test_case/1 requires assertions" do
      suite = suite_fixture()

      attrs = %{
        suite_id: suite.id,
        variable_values: %{}
      }

      assert {:error, changeset} = Evals.create_test_case(attrs)
      assert "can't be blank" in errors_on(changeset).assertions
    end

    test "list_test_cases/0 returns all test cases" do
      test_case = test_case_fixture()
      test_cases = Evals.list_test_cases()

      assert length(test_cases) == 1
      assert hd(test_cases).id == test_case.id
    end

    test "get_test_case!/1 returns the test case with given id" do
      test_case = test_case_fixture()
      fetched = Evals.get_test_case!(test_case.id)

      assert fetched.id == test_case.id
    end

    test "update_test_case/2 updates the test case" do
      test_case = test_case_fixture()

      assert {:ok, updated} =
               Evals.update_test_case(test_case, %{variable_values: %{"new" => "value"}})

      assert updated.variable_values == %{"new" => "value"}
    end

    test "delete_test_case/1 deletes the test case" do
      test_case = test_case_fixture()

      assert {:ok, _test_case} = Evals.delete_test_case(test_case)
      assert_raise Ecto.NoResultsError, fn -> Evals.get_test_case!(test_case.id) end
    end

    test "change_test_case/1 returns a test case changeset" do
      test_case = test_case_fixture()
      changeset = Evals.change_test_case(test_case)

      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "suite_runs" do
    test "create_suite_run/1 creates a suite run with valid attributes" do
      suite = suite_fixture()
      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Template {{var}}")
      provider = provider_fixture()

      attrs = %{
        suite_id: suite.id,
        prompt_version_id: version.id,
        provider_id: provider.id,
        results: [%{"test_case_id" => "123", "passed" => true}],
        passed: 1,
        failed: 0
      }

      assert {:ok, suite_run} = Evals.create_suite_run(attrs)
      assert suite_run.suite_id == suite.id
      assert suite_run.prompt_version_id == version.id
      assert suite_run.provider_id == provider.id
      assert suite_run.results == [%{"test_case_id" => "123", "passed" => true}]
      assert suite_run.passed == 1
      assert suite_run.failed == 0
    end

    test "create_suite_run/1 requires suite_id" do
      attrs = %{results: [], passed: 0, failed: 0}

      assert {:error, changeset} = Evals.create_suite_run(attrs)
      assert "can't be blank" in errors_on(changeset).suite_id
    end

    test "create_suite_run/1 requires prompt_version_id" do
      suite = suite_fixture()

      attrs = %{suite_id: suite.id, results: [], passed: 0, failed: 0}

      assert {:error, changeset} = Evals.create_suite_run(attrs)
      assert "can't be blank" in errors_on(changeset).prompt_version_id
    end

    test "create_suite_run/1 requires provider_id" do
      suite = suite_fixture()
      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Template {{var}}")

      attrs = %{
        suite_id: suite.id,
        prompt_version_id: version.id,
        results: [],
        passed: 0,
        failed: 0
      }

      assert {:error, changeset} = Evals.create_suite_run(attrs)
      assert "can't be blank" in errors_on(changeset).provider_id
    end

    test "list_suite_runs/0 returns all suite runs" do
      suite_run = suite_run_fixture()
      suite_runs = Evals.list_suite_runs()

      assert length(suite_runs) == 1
      assert hd(suite_runs).id == suite_run.id
    end

    test "get_suite_run!/1 returns the suite run with given id" do
      suite_run = suite_run_fixture()
      fetched = Evals.get_suite_run!(suite_run.id)

      assert fetched.id == suite_run.id
    end

    test "delete_suite_run/1 deletes the suite run" do
      suite_run = suite_run_fixture()

      assert {:ok, _suite_run} = Evals.delete_suite_run(suite_run)
      assert_raise Ecto.NoResultsError, fn -> Evals.get_suite_run!(suite_run.id) end
    end

    test "changeset accepts avg_cost_usd, avg_latency_ms, and avg_score" do
      suite = suite_fixture()
      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Template {{var}}")
      provider = provider_fixture()

      attrs = %{
        suite_id: suite.id,
        prompt_version_id: version.id,
        provider_id: provider.id,
        avg_cost_usd: Decimal.new("0.0042"),
        avg_latency_ms: 350,
        avg_score: Decimal.new("83.3")
      }

      changeset = SuiteRun.changeset(%SuiteRun{}, attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :avg_cost_usd) == Decimal.new("0.0042")
      assert Ecto.Changeset.get_change(changeset, :avg_latency_ms) == 350
      assert Ecto.Changeset.get_change(changeset, :avg_score) == Decimal.new("83.3")
    end

    test "list_suite_runs_for_suite/1 returns runs for specific suite" do
      suite1 = suite_fixture(%{name: "Suite 1"})
      suite2 = suite_fixture(%{name: "Suite 2"})
      run1 = suite_run_fixture(%{suite_id: suite1.id})
      _run2 = suite_run_fixture(%{suite_id: suite2.id})

      runs = Evals.list_suite_runs_for_suite(suite1.id)

      assert length(runs) == 1
      assert hd(runs).id == run1.id
    end

    test "list_suite_runs_for_suite_with_associations/1 preloads associations" do
      suite = suite_fixture()
      run = suite_run_fixture(%{suite_id: suite.id})

      runs = Evals.list_suite_runs_for_suite_with_associations(suite.id)

      assert length(runs) == 1
      loaded_run = hd(runs)
      assert loaded_run.id == run.id
      refute match?(%Ecto.Association.NotLoaded{}, loaded_run.prompt_version)
      refute match?(%Ecto.Association.NotLoaded{}, loaded_run.provider)
    end

    test "reload_suite_run_with_associations/1 reloads associations" do
      run = suite_run_fixture()

      loaded = Evals.reload_suite_run_with_associations(run)

      refute match?(%Ecto.Association.NotLoaded{}, loaded.prompt_version)
      refute match?(%Ecto.Association.NotLoaded{}, loaded.provider)
    end

    test "pass_rates_by_prompt/0 calculates pass rates grouped by prompt" do
      prompt = prompt_fixture(%{name: "Test Prompt"})
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Template {{var}}")
      suite = suite_fixture(%{prompt_id: prompt.id})
      provider = provider_fixture()

      # Create suite runs with different pass/fail counts
      _run1 =
        suite_run_fixture(%{
          suite_id: suite.id,
          prompt_version_id: version.id,
          provider_id: provider.id,
          passed: 8,
          failed: 2
        })

      _run2 =
        suite_run_fixture(%{
          suite_id: suite.id,
          prompt_version_id: version.id,
          provider_id: provider.id,
          passed: 7,
          failed: 3
        })

      results = Evals.pass_rates_by_prompt()

      assert length(results) == 1
      result = hd(results)
      assert result.prompt_id == prompt.id
      assert result.prompt_name == "Test Prompt"
      assert result.total_passed == 15
      assert result.total_failed == 5
    end

    test "retry_suite_run_test_case/2 replaces the existing result and recalculates aggregates" do
      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Hello {{name}}")
      suite = suite_fixture(%{prompt_id: prompt.id})

      provider =
        provider_fixture(%{
          pricing: %{"input" => 1000.0, "output" => 2000.0}
        })

      passing_test_case =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"name" => "Bob"},
          assertions: [%{"type" => "contains", "value" => "Hello"}]
        })

      retried_test_case =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"name" => "Alice"},
          assertions: [%{"type" => "contains", "value" => "Hello"}]
        })

      suite_run =
        suite_run_fixture(%{
          suite_id: suite.id,
          prompt_version_id: version.id,
          provider_id: provider.id,
          passed: 1,
          failed: 1,
          avg_cost_usd: Decimal.new("0.003"),
          avg_latency_ms: 140,
          results: [
            %{
              "test_case_id" => passing_test_case.id,
              "passed" => true,
              "output" => "Hello Bob",
              "assertion_results" => [
                %{"type" => "contains", "passed" => true, "value" => "Hello"}
              ],
              "cost_usd" => 0.003,
              "latency_ms" => 140
            },
            %{
              "test_case_id" => retried_test_case.id,
              "passed" => false,
              "output" => "Rate limit exceeded",
              "assertion_results" => [],
              "cost_usd" => nil,
              "latency_ms" => nil
            }
          ]
        })

      expect(HttpClientMock, :request, fn _model, prompt, _opts ->
        assert prompt == "Hello Alice"

        {:ok, build_mock_response("Hello Alice", 5, 10)}
      end)

      assert {:ok, updated_suite_run} =
               Evals.retry_suite_run_test_case(suite_run, retried_test_case.id)

      retried_result =
        Enum.find(updated_suite_run.results, fn result ->
          result["test_case_id"] == retried_test_case.id
        end)

      assert retried_result["passed"] == true
      assert retried_result["output"] == "Hello Alice"
      assert retried_result["retry_count"] == 1
      assert is_binary(retried_result["retried_at"])
      assert updated_suite_run.passed == 2
      assert updated_suite_run.failed == 0
      assert Decimal.compare(updated_suite_run.avg_cost_usd, Decimal.new("0")) == :gt
      assert updated_suite_run.avg_latency_ms >= 0
      assert updated_suite_run.cost_sample_count == 2
      assert updated_suite_run.latency_sample_count == 2
      assert Decimal.compare(updated_suite_run.total_cost_usd, Decimal.new("0")) == :gt
      assert updated_suite_run.total_latency_ms >= 0

      reloaded_suite_run = Evals.get_suite_run!(suite_run.id)

      assert Enum.any?(reloaded_suite_run.results, fn result ->
               result["test_case_id"] == retried_test_case.id and
                 result["retry_count"] == 1 and result["output"] == "Hello Alice"
             end)
    end
  end

  describe "execute_suite/3" do
    test "executes multi-turn cases with the rendered prompt as system context" do
      expect(HttpClientMock, :request, fn _model, messages, _opts ->
        assert messages == [
                 %{role: :system, content: "Answer in a calm tone"},
                 %{role: :user, content: "My name is Alice"},
                 %{role: :assistant, content: "Hello Alice"},
                 %{role: :user, content: "What is my name?"}
               ]

        {:ok, build_mock_response("Your name is Alice", 12, 5)}
      end)

      suite = suite_fixture()
      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Answer in a {{tone}} tone")
      provider = provider_fixture()

      _test_case =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"tone" => "calm", "name" => "Alice"},
          messages: [
            %{"role" => "user", "content" => "My name is {{name}}"},
            %{"role" => "assistant", "content" => "Hello {{name}}"},
            %{"role" => "user", "content" => "What is my name?"}
          ],
          assertions: [%{"type" => "contains", "value" => "Alice"}]
        })

      assert {:ok, suite_run} = Evals.execute_suite(suite, version, provider)
      assert suite_run.passed == 1
      assert [result] = suite_run.results

      assert result["artifacts"]["steps"] |> hd() |> get_in(["input", "messages"]) == [
               %{"role" => "user", "content" => "My name is Alice"},
               %{"role" => "assistant", "content" => "Hello Alice"},
               %{"role" => "user", "content" => "What is my name?"}
             ]
    end

    test "execute_suite captures avg_cost_usd and avg_latency_ms" do
      mock_response = build_mock_response("Mock response", 5, 10)

      # Use stub for concurrent test case execution
      stub(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      suite = suite_fixture()
      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Test {{input}}")
      provider = provider_fixture()

      # Create test cases that will succeed
      _tc1 =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"input" => "value1"},
          assertions: [%{"type" => "contains", "value" => "Mock"}]
        })

      _tc2 =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"input" => "value2"},
          assertions: [%{"type" => "contains", "value" => "response"}]
        })

      assert {:ok, suite_run} = Evals.execute_suite(suite, version, provider)

      assert suite_run.avg_cost_usd != nil
      assert suite_run.avg_latency_ms != nil
      assert Decimal.compare(suite_run.avg_cost_usd, Decimal.new("0")) == :gt
      assert suite_run.avg_latency_ms >= 0
      assert suite_run.cost_sample_count == 2
      assert suite_run.latency_sample_count == 2
      assert Decimal.compare(suite_run.total_cost_usd, Decimal.new("0")) == :gt
      assert suite_run.total_latency_ms >= 0
    end

    test "execute_suite handles partial failures in metrics" do
      mock_response = build_mock_response("Mock response", 5, 10)

      # Use stub for concurrent test case execution
      stub(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      suite = suite_fixture()
      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Test {{input}}")
      provider = provider_fixture()

      # Create one passing and one failing test case
      _tc1 =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"input" => "value1"},
          assertions: [%{"type" => "contains", "value" => "Mock"}]
        })

      _tc2 =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"input" => "value2"},
          assertions: [%{"type" => "contains", "value" => "NOTFOUND"}]
        })

      assert {:ok, suite_run} = Evals.execute_suite(suite, version, provider)

      # Should still have metrics from successful tests
      assert is_nil(suite_run.avg_cost_usd) or
               Decimal.compare(suite_run.avg_cost_usd, Decimal.new("0")) == :gt

      assert is_nil(suite_run.avg_latency_ms) or suite_run.avg_latency_ms >= 0
    end

    test "executes suite with passing test cases" do
      mock_response = build_mock_response("Mock response", 5, 10)

      # Use stub for concurrent test case execution
      stub(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      suite = suite_fixture()
      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Hello {{name}}")
      provider = provider_fixture()

      _tc1 =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"name" => "Alice"},
          assertions: [%{"type" => "contains", "value" => "Mock"}]
        })

      _tc2 =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"name" => "Bob"},
          assertions: [%{"type" => "contains", "value" => "Mock"}]
        })

      assert {:ok, suite_run} = Evals.execute_suite(suite, version, provider)
      assert suite_run.suite_id == suite.id
      assert suite_run.prompt_version_id == version.id
      assert suite_run.provider_id == provider.id
      assert suite_run.passed == 2
      assert suite_run.failed == 0
      assert length(suite_run.results) == 2

      assert Enum.all?(suite_run.results, &(&1["passed"] == true))

      Enum.each(suite_run.results, fn result ->
        assert result["artifacts"]["schema_version"] == 1
        assert [%{"status" => "completed", "metrics" => metrics}] = result["artifacts"]["steps"]
        assert metrics["score"] == 100.0
        assert [%{"reason" => "Output contains expected value"}] = metrics["results"]
      end)
    end

    test "executes suite with failing test cases" do
      mock_response = build_mock_response("Mock response", 5, 10)

      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      suite = suite_fixture()
      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Say {{word}}")
      provider = provider_fixture()

      _tc1 =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"word" => "hello"},
          assertions: [%{"type" => "contains", "value" => "NOTFOUND"}]
        })

      assert {:ok, suite_run} = Evals.execute_suite(suite, version, provider)
      assert suite_run.passed == 0
      assert suite_run.failed == 1
    end

    test "evaluates contains assertion" do
      mock_response = build_mock_response("Mock response", 5, 10)

      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      suite = suite_fixture()
      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Test {{input}}")
      provider = provider_fixture()

      _tc =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"input" => "value"},
          assertions: [%{"type" => "contains", "value" => "Mock"}]
        })

      assert {:ok, suite_run} = Evals.execute_suite(suite, version, provider)
      assert suite_run.passed == 1
      assert suite_run.failed == 0

      assert [
               %{
                 "assertion_results" => [
                   %{
                     "reason" => "Output contains expected value",
                     "metadata" => %{}
                   }
                 ]
               }
             ] = suite_run.results
    end

    test "evaluates not_contains assertion" do
      mock_response = build_mock_response("Mock response", 5, 10)

      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      suite = suite_fixture()
      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Test {{input}}")
      provider = provider_fixture()

      _tc =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"input" => "value"},
          assertions: [%{"type" => "not_contains", "value" => "NOTFOUND"}]
        })

      assert {:ok, suite_run} = Evals.execute_suite(suite, version, provider)
      assert suite_run.passed == 1
    end

    test "evaluates regex assertion" do
      mock_response = build_mock_response("Mock response", 5, 10)

      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      suite = suite_fixture()
      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Test {{input}}")
      provider = provider_fixture()

      _tc =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"input" => "value"},
          assertions: [%{"type" => "regex", "value" => "Mock.*response"}]
        })

      assert {:ok, suite_run} = Evals.execute_suite(suite, version, provider)
      assert suite_run.passed == 1
    end

    test "evaluates exact_match assertion" do
      mock_response = build_mock_response("Mock response", 5, 10)

      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      suite = suite_fixture()
      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Test {{input}}")
      provider = provider_fixture()

      _tc =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"input" => "value"},
          assertions: [%{"type" => "exact_match", "value" => "Mock response"}]
        })

      assert {:ok, suite_run} = Evals.execute_suite(suite, version, provider)
      assert suite_run.passed == 1
    end

    test "persists rubric judge evidence separately from model execution" do
      provider = provider_fixture(%{model: "output-model"})
      judge_provider = provider_fixture(%{name: "Judge", model: "judge-model"})

      expect(HttpClientMock, :request, 2, fn
        "openai:output-model", _prompt, _opts ->
          {:ok, build_mock_response("Paris", 5, 2)}

        "openai:judge-model", _messages, _opts ->
          {:ok,
           build_mock_response(
             ~s({"score":95,"reasoning":"The response matches the reference."}),
             30,
             8
           )}
      end)

      suite = suite_fixture()
      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Capital: {{country}}")

      _test_case =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"country" => "France"},
          assertions: [
            %{
              "type" => "rubric_judge",
              "rubric" => "The response must name the correct capital.",
              "provider_id" => judge_provider.id,
              "threshold" => 90,
              "expected" => "Paris"
            }
          ]
        })

      assert {:ok, suite_run} = Evals.execute_suite(suite, version, provider)
      assert suite_run.passed == 1

      assert [%{"assertion_results" => [assertion_result], "artifacts" => artifacts}] =
               suite_run.results

      assert assertion_result["score"] == 95.0
      assert assertion_result["evaluator"]["model"] == "judge-model"
      assert assertion_result["evaluator"]["input_tokens"] == 30

      assert get_in(artifacts, ["steps", Access.at(0), "metrics", "results", Access.at(0)]) ==
               assertion_result
    end

    test "evaluates multiple assertions per test case" do
      mock_response = build_mock_response("Mock response", 5, 10)

      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      suite = suite_fixture()
      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Test {{input}}")
      provider = provider_fixture()

      _tc =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"input" => "value"},
          assertions: [
            %{"type" => "contains", "value" => "Mock"},
            %{"type" => "not_contains", "value" => "NOTFOUND"},
            %{"type" => "regex", "value" => "response"}
          ]
        })

      assert {:ok, suite_run} = Evals.execute_suite(suite, version, provider)
      assert suite_run.passed == 1
    end

    test "fails if any assertion fails" do
      suite = suite_fixture()
      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Test {{input}}")
      provider = provider_fixture()

      _tc =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"input" => "value"},
          assertions: [
            %{"type" => "contains", "value" => "Mock"},
            %{"type" => "contains", "value" => "NOTFOUND"}
          ]
        })

      assert {:ok, suite_run} = Evals.execute_suite(suite, version, provider)
      assert suite_run.failed == 1
    end

    test "json_field passes for exact string scalar matches" do
      assert {:ok, suite_run} = execute_json_field_suite(~s({"status":"ok"}), "status", "ok")

      assert suite_run.passed == 1
      assert suite_run.failed == 0

      assert [%{"assertion_results" => [%{"actual_value" => "ok", "passed" => true}]}] =
               suite_run.results
    end

    test "json_field fails on number and string scalar mismatches" do
      assert {:ok, suite_run} = execute_json_field_suite(~s({"count":1}), "count", "1")

      assert suite_run.passed == 0
      assert suite_run.failed == 1

      assert [%{"assertion_results" => [%{"actual_value" => 1, "passed" => false}]}] =
               suite_run.results
    end

    test "json_field fails on boolean and string scalar mismatches" do
      assert {:ok, suite_run} = execute_json_field_suite(~s({"active":true}), "active", "true")

      assert suite_run.passed == 0
      assert suite_run.failed == 1

      assert [%{"assertion_results" => [%{"actual_value" => true, "passed" => false}]}] =
               suite_run.results
    end

    test "json_field fails on nil and string scalar mismatches" do
      assert {:ok, suite_run} = execute_json_field_suite(~s({"note":null}), "note", "nil")

      assert suite_run.passed == 0
      assert suite_run.failed == 1

      assert [%{"assertion_results" => [%{"actual_value" => nil, "passed" => false}]}] =
               suite_run.results
    end

    test "json_deep_compare records partial scores and passes when threshold is met" do
      expected = %{"name" => "John", "age" => 30, "city" => "NYC", "job" => "Engineer"}

      assert {:ok, suite_run} =
               execute_json_deep_compare_suite(
                 ~s({"name":"John","age":25,"city":"NYC","job":"Engineer"}),
                 expected,
                 75.0
               )

      assert suite_run.passed == 1
      assert suite_run.failed == 0
      assert Decimal.equal?(suite_run.avg_score, Decimal.new("75.0"))

      assert [
               %{
                 "score" => 75.0,
                 "assertion_results" => [
                   %{
                     "type" => "json_deep_compare",
                     "passed" => true,
                     "score" => 75.0,
                     "score_details" => %{
                       "matches" => 3,
                       "total" => 4,
                       "field_scores" => %{
                         "name" => 1,
                         "age" => 0,
                         "city" => 1,
                         "job" => 1
                       }
                     }
                   }
                 ]
               }
             ] = suite_run.results
    end

    test "json_deep_compare defaults to strict matching without a threshold" do
      expected = %{"name" => "John", "age" => 30}

      assert {:ok, suite_run} =
               execute_json_deep_compare_suite(
                 ~s({"name":"John","age":25}),
                 expected
               )

      assert suite_run.passed == 0
      assert suite_run.failed == 1
      assert Decimal.equal?(suite_run.avg_score, Decimal.new("50.0"))

      assert [
               %{
                 "passed" => false,
                 "score" => 50.0,
                 "assertion_results" => [%{"passed" => false, "score" => 50.0}]
               }
             ] = suite_run.results
    end
  end

  describe "test_case_documents" do
    test "create_test_case_document/1 creates a document" do
      test_case = test_case_fixture()

      attrs = %{
        test_case_id: test_case.id,
        filename: "doc.pdf",
        content_type: "application/pdf",
        data: <<1, 2, 3>>,
        size_bytes: 3
      }

      assert {:ok, document} = Evals.create_test_case_document(attrs)
      assert document.test_case_id == test_case.id
      assert document.filename == "doc.pdf"
      assert document.content_type == "application/pdf"
    end

    test "create_test_case_document/1 rejects pre-externalized document attrs" do
      test_case = test_case_fixture()

      assert {:error, changeset} =
               Evals.create_test_case_document(%{
                 test_case_id: test_case.id,
                 filename: "doc.pdf",
                 content_type: "application/pdf",
                 size_bytes: 3,
                 storage_key: "test_case_documents/doc-id/doc.pdf",
                 storage_backend: "local"
               })

      assert "can't be blank" in errors_on(changeset).data
      assert "must be blank for uploaded documents" in errors_on(changeset).storage_key
      assert "must be blank for uploaded documents" in errors_on(changeset).storage_backend
    end

    test "delete_test_case_document/1 deletes a document" do
      test_case = test_case_fixture()

      {:ok, document} =
        Evals.create_test_case_document(%{
          test_case_id: test_case.id,
          filename: "doc.pdf",
          content_type: "application/pdf",
          data: <<1, 2, 3>>,
          size_bytes: 3
        })

      assert {:ok, _deleted} = Evals.delete_test_case_document(document)
    end

    test "get_test_case_with_documents!/1 preloads documents" do
      test_case = test_case_fixture()

      {:ok, _doc1} =
        Evals.create_test_case_document(%{
          test_case_id: test_case.id,
          filename: "doc1.pdf",
          content_type: "application/pdf",
          data: <<1, 2, 3>>,
          size_bytes: 3
        })

      {:ok, _doc2} =
        Evals.create_test_case_document(%{
          test_case_id: test_case.id,
          filename: "doc2.pdf",
          content_type: "application/pdf",
          data: <<4, 5, 6>>,
          size_bytes: 3
        })

      loaded = Evals.get_test_case_with_documents!(test_case.id)

      refute match?(%Ecto.Association.NotLoaded{}, loaded.documents)
      assert length(loaded.documents) == 2
    end

    test "max_size_bytes/0 returns correct limit" do
      assert TestCaseDocument.max_size_bytes() == 10 * 1024 * 1024
    end

    test "supported_types/0 returns list of MIME types" do
      types = TestCaseDocument.supported_types()
      assert is_list(types)
      assert "application/pdf" in types
      assert "image/png" in types
    end

    test "create_test_case_document/1 stores document outside the database when external storage is configured" do
      root = temp_storage_root()
      configure_storage(adapter: Aludel.Interfaces.Storage.Adapters.Local, root: root)
      test_case = test_case_fixture()

      assert {:ok, document} =
               Evals.create_test_case_document(%{
                 test_case_id: test_case.id,
                 filename: "diagram.png",
                 content_type: "image/png",
                 data: <<1, 2, 3, 4>>,
                 size_bytes: 4
               })

      assert document.data == nil
      assert document.storage_backend == "local"
      assert is_binary(document.storage_key)

      assert File.read!(Local.path_for(document.storage_key)) ==
               <<1, 2, 3, 4>>
    end

    test "create_test_case_document/1 surfaces upload failures and does not insert a row" do
      configure_storage(adapter: StorageMock)
      test_case = test_case_fixture()

      expect(StorageMock, :put, fn _key, _data, _content_type, _config ->
        {:error, :storage_unavailable}
      end)

      assert {:error, changeset} =
               Evals.create_test_case_document(%{
                 test_case_id: test_case.id,
                 filename: "diagram.png",
                 content_type: "image/png",
                 data: <<1, 2, 3, 4>>,
                 size_bytes: 4
               })

      assert "storage_unavailable" in errors_on(changeset).data
      assert Repo.aggregate(TestCaseDocument, :count, :id) == 0
    end

    test "create_test_case_document/1 deletes the uploaded file when insert fails" do
      configure_storage(adapter: StorageMock)
      test_case = test_case_fixture()
      storage_key = "test_case_documents/shared/diagram.png"

      Repo.insert!(
        TestCaseDocument.changeset(%TestCaseDocument{}, %{
          test_case_id: test_case.id,
          filename: "existing.png",
          content_type: "image/png",
          size_bytes: 4,
          storage_key: storage_key,
          storage_backend: Atom.to_string(StorageMock)
        })
      )

      expect(StorageMock, :put, fn _key, _data, _content_type, _config ->
        {:ok, storage_key}
      end)

      expect(StorageMock, :delete, fn ^storage_key, config ->
        assert config == []
        :ok
      end)

      assert {:error, changeset} =
               Evals.create_test_case_document(%{
                 test_case_id: test_case.id,
                 filename: "diagram.png",
                 content_type: "image/png",
                 data: <<1, 2, 3, 4>>,
                 size_bytes: 4
               })

      assert "has already been taken" in errors_on(changeset).storage_key
      assert Repo.aggregate(TestCaseDocument, :count, :id) == 1
    end

    test "delete_test_case_document/1 removes externally stored files" do
      root = temp_storage_root()
      configure_storage(adapter: Aludel.Interfaces.Storage.Adapters.Local, root: root)
      test_case = test_case_fixture()

      assert {:ok, document} =
               Evals.create_test_case_document(%{
                 test_case_id: test_case.id,
                 filename: "diagram.png",
                 content_type: "image/png",
                 data: <<1, 2, 3, 4>>,
                 size_bytes: 4
               })

      path = Local.path_for(document.storage_key)

      assert File.exists?(path)
      assert {:ok, _deleted} = Evals.delete_test_case_document(document)
      refute File.exists?(path)
    end

    test "delete_test_case_document/1 rolls back when external deletion fails" do
      configure_storage(adapter: StorageMock)
      test_case = test_case_fixture()

      expect(StorageMock, :put, fn key, _data, _content_type, _config ->
        {:ok, key}
      end)

      assert {:ok, document} =
               Evals.create_test_case_document(%{
                 test_case_id: test_case.id,
                 filename: "diagram.png",
                 content_type: "image/png",
                 data: <<1, 2, 3, 4>>,
                 size_bytes: 4
               })

      expect(StorageMock, :delete, fn key, config ->
        assert key == document.storage_key
        assert config == []
        {:error, :permission_denied}
      end)

      assert {:error, changeset} = Evals.delete_test_case_document(document)
      assert "permission_denied" in errors_on(changeset).data
      assert Repo.get(TestCaseDocument, document.id)
    end
  end

  describe "execute_suite with documents" do
    test "passes documents to LLM.call" do
      suite = suite_fixture()
      test_case = test_case_fixture(%{suite_id: suite.id})

      {:ok, _doc} =
        Aludel.Evals.create_test_case_document(%{
          test_case_id: test_case.id,
          filename: "test.png",
          content_type: "image/png",
          data: <<1, 2, 3>>,
          size_bytes: 3
        })

      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Describe {{input}}")

      provider =
        provider_fixture(%{
          provider: :openai,
          model: "gpt-4o"
        })

      expect(HttpClientMock, :request, fn _model, _prompt, opts ->
        assert [%{data: <<1, 2, 3>>, content_type: "image/png"}] =
                 Keyword.fetch!(opts, :documents)

        {:ok, build_mock_response("described", 5, 10)}
      end)

      assert {:ok, suite_run} = Aludel.Evals.execute_suite(suite, version, provider)
      assert suite_run.passed + suite_run.failed > 0
    end

    test "loads externally stored documents before calling the LLM" do
      root = temp_storage_root()
      configure_storage(adapter: Aludel.Interfaces.Storage.Adapters.Local, root: root)

      suite = suite_fixture()
      test_case = test_case_fixture(%{suite_id: suite.id})

      {:ok, _doc} =
        Aludel.Evals.create_test_case_document(%{
          test_case_id: test_case.id,
          filename: "first.png",
          content_type: "image/png",
          data: <<9, 8, 7>>,
          size_bytes: 3
        })

      {:ok, _doc} =
        Aludel.Evals.create_test_case_document(%{
          test_case_id: test_case.id,
          filename: "second.png",
          content_type: "image/png",
          data: <<6, 5, 4>>,
          size_bytes: 3
        })

      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Describe {{input}}")

      provider =
        provider_fixture(%{
          provider: :openai,
          model: "gpt-4o"
        })

      expect(HttpClientMock, :request, fn _model, _prompt, opts ->
        actual_documents =
          opts
          |> Keyword.fetch!(:documents)
          |> Enum.sort_by(fn %{data: data, content_type: content_type} ->
            {content_type, Base.encode16(data)}
          end)

        expected_documents =
          [
            %{data: <<9, 8, 7>>, content_type: "image/png"},
            %{data: <<6, 5, 4>>, content_type: "image/png"}
          ]
          |> Enum.sort_by(fn %{data: data, content_type: content_type} ->
            {content_type, Base.encode16(data)}
          end)

        assert actual_documents == expected_documents

        {:ok, build_mock_response("loaded", 5, 10)}
      end)

      assert {:ok, suite_run} = Aludel.Evals.execute_suite(suite, version, provider)
      assert suite_run.passed + suite_run.failed > 0
    end

    test "returns a failed test case result when document loading exits" do
      configure_storage(adapter: StorageMock)

      suite = suite_fixture()
      test_case = test_case_fixture(%{suite_id: suite.id})

      Repo.insert!(
        TestCaseDocument.changeset(%TestCaseDocument{}, %{
          test_case_id: test_case.id,
          filename: "crash.png",
          content_type: "image/png",
          size_bytes: 3,
          storage_key: "test_case_documents/doc-id/crash.png",
          storage_backend: Atom.to_string(StorageMock)
        })
      )

      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Describe {{input}}")
      provider = provider_fixture(%{provider: :openai, model: "gpt-4o"})

      expect(StorageMock, :get, fn _key, _config ->
        exit(:boom)
      end)

      assert {:ok, suite_run} = Aludel.Evals.execute_suite(suite, version, provider)
      assert suite_run.failed == 1

      assert [%{"output" => output}] = suite_run.results
      assert output == "Failed to load document crash.png: boom"

      assert [
               %{
                 "artifacts" => %{
                   "schema_version" => 1,
                   "steps" => [
                     %{
                       "status" => "failed",
                       "error" => %{"type" => "document_storage_error"}
                     }
                   ]
                 }
               }
             ] = suite_run.results
    end

    test "returns a failed test case result when document loading times out" do
      configure_storage(adapter: StorageMock)
      configure_evals(document_load_timeout_ms: 1)

      suite = suite_fixture()
      test_case = test_case_fixture(%{suite_id: suite.id})

      Repo.insert!(
        TestCaseDocument.changeset(%TestCaseDocument{}, %{
          test_case_id: test_case.id,
          filename: "slow.png",
          content_type: "image/png",
          size_bytes: 3,
          storage_key: "test_case_documents/doc-id/slow.png",
          storage_backend: Atom.to_string(StorageMock)
        })
      )

      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Describe {{input}}")
      provider = provider_fixture(%{provider: :openai, model: "gpt-4o"})

      expect(StorageMock, :get, fn _key, _config ->
        Process.sleep(25)
        {:ok, <<1, 2, 3>>}
      end)

      assert {:ok, suite_run} = Aludel.Evals.execute_suite(suite, version, provider)
      assert suite_run.failed == 1

      assert [%{"output" => output}] = suite_run.results
      assert output =~ "Failed to load document unknown_document:"
      assert output =~ "timeout"
    end

    test "returns a failed test case result when document loading raises" do
      configure_storage(adapter: StorageMock)

      suite = suite_fixture()
      test_case = test_case_fixture(%{suite_id: suite.id})

      Repo.insert!(
        TestCaseDocument.changeset(%TestCaseDocument{}, %{
          test_case_id: test_case.id,
          filename: "crash.png",
          content_type: "image/png",
          size_bytes: 3,
          storage_key: "test_case_documents/doc-id/crash.png",
          storage_backend: Atom.to_string(StorageMock)
        })
      )

      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Describe {{input}}")
      provider = provider_fixture(%{provider: :openai, model: "gpt-4o"})

      expect(StorageMock, :get, fn _key, _config ->
        raise "boom"
      end)

      assert {:ok, suite_run} = Aludel.Evals.execute_suite(suite, version, provider)
      assert suite_run.failed == 1

      assert [%{"output" => output}] = suite_run.results
      assert output == "Failed to load document crash.png: boom"
    end
  end

  describe "launch_suite_execution/4" do
    test "launches suite execution, monitors it, and sends the completion result" do
      prompt = prompt_fixture_with_version(%{template: "Hello {{name}}"})
      suite = suite_fixture(%{prompt_id: prompt.id})
      provider = provider_fixture()
      version = List.first(prompt.versions)

      assert {:ok, monitor_ref} =
               Evals.launch_suite_execution(self(), suite.id, version.id, provider.id)

      assert_receive {:suite_completed, {:ok, suite_run}}, 1000
      assert suite_run.suite_id == suite.id
      assert suite_run.prompt_version_id == version.id
      assert suite_run.provider_id == provider.id
      assert_receive {:DOWN, ^monitor_ref, :process, _task_pid, :normal}, 1000
    end

    test "returns structured failure results through the launched task" do
      prompt = prompt_fixture_with_version(%{template: "Hello {{name}}"})
      suite = suite_fixture(%{prompt_id: prompt.id})
      version = List.first(prompt.versions)

      assert {:ok, monitor_ref} =
               Evals.launch_suite_execution(self(), suite.id, version.id, Ecto.UUID.generate())

      assert_receive {:suite_completed, {:error, :provider_not_found}}, 1000
      assert_receive {:DOWN, ^monitor_ref, :process, _task_pid, :normal}, 1000
    end
  end

  defp build_mock_response(text, input_tokens, output_tokens) do
    %{
      content: text,
      input_tokens: input_tokens,
      output_tokens: output_tokens
    }
  end

  defp configure_storage(config) do
    original_config = Application.get_env(:aludel, Aludel.Storage, [])
    Application.put_env(:aludel, Aludel.Storage, config)

    on_exit(fn ->
      Application.put_env(:aludel, Aludel.Storage, original_config)
    end)
  end

  defp configure_evals(config) do
    original_config = Application.get_env(:aludel, :evals, [])
    Application.put_env(:aludel, :evals, config)

    on_exit(fn ->
      Application.put_env(:aludel, :evals, original_config)
    end)
  end

  defp temp_storage_root do
    root = Path.join(System.tmp_dir!(), "aludel-storage-#{Ecto.UUID.generate()}")
    File.mkdir_p!(root)
    root
  end

  defp execute_json_field_suite(output, field, expected) do
    mock_response = build_mock_response(output, 5, 10)

    expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
      {:ok, mock_response}
    end)

    suite = suite_fixture()
    prompt = prompt_fixture()
    {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Return JSON")
    provider = provider_fixture()

    _test_case =
      test_case_fixture(%{
        suite_id: suite.id,
        variable_values: %{},
        assertions: [%{"type" => "json_field", "field" => field, "expected" => expected}]
      })

    Evals.execute_suite(suite, version, provider)
  end

  defp execute_json_deep_compare_suite(output, expected, threshold \\ nil) do
    mock_response = build_mock_response(output, 5, 10)

    expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
      {:ok, mock_response}
    end)

    suite = suite_fixture()
    prompt = prompt_fixture()
    {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Return JSON")
    provider = provider_fixture()

    assertion =
      %{
        "type" => "json_deep_compare",
        "expected" => expected
      }
      |> then(fn assertion ->
        if is_nil(threshold), do: assertion, else: Map.put(assertion, "threshold", threshold)
      end)

    _test_case =
      test_case_fixture(%{
        suite_id: suite.id,
        variable_values: %{},
        assertions: [assertion]
      })

    Evals.execute_suite(suite, version, provider)
  end
end
