defmodule Aludel.RunsTest do
  use Aludel.DataCase

  import Mox

  alias Aludel.Interfaces.HttpClientMock
  alias Aludel.Runs
  alias Aludel.Runs.Execution
  alias Aludel.Runs.Run
  alias Aludel.Runs.RunResult

  import Aludel.EvalsFixtures
  import Aludel.PromptsFixtures
  import Aludel.ProvidersFixtures

  setup :set_mox_global
  setup :verify_on_exit!

  describe "runs" do
    @valid_attrs %{
      name: "Test Run",
      variable_values: %{"user" => "Alice", "topic" => "AI"}
    }
    @update_attrs %{
      name: "Updated Run",
      variable_values: %{"user" => "Bob", "topic" => "ML"}
    }
    @invalid_attrs %{prompt_version_id: nil}

    setup do
      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Hello {{user}}")
      {:ok, prompt_version: version}
    end

    test "total_cost/0 sums suite test case costs from suite run results" do
      # Create a run result with cost
      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Template")
      provider = provider_fixture()

      {:ok, run} =
        Runs.create_run(%{
          prompt_version_id: version.id,
          variable_values: %{"user" => "Test"}
        })

      {:ok, _result} =
        Runs.create_run_result(%{
          run_id: run.id,
          provider_id: provider.id,
          output: "Output",
          cost_usd: 0.001,
          status: :completed
        })

      # Create a suite run with cost
      _suite_run =
        suite_run_fixture(%{
          avg_cost_usd: Decimal.new("0.005"),
          results: [
            %{"cost_usd" => 0.004, "latency_ms" => 100, "passed" => true},
            %{"cost_usd" => 0.006, "latency_ms" => 120, "passed" => false},
            %{"cost_usd" => nil, "latency_ms" => nil, "passed" => false}
          ]
        })

      total = Runs.total_cost()

      # Should include both run result cost (0.001) and suite execution cost (0.010)
      assert_in_delta total, 0.011, 0.0001
    end

    test "list_runs/0 returns all runs", %{prompt_version: version} do
      attrs = Map.put(@valid_attrs, :prompt_version_id, version.id)
      {:ok, run} = Runs.create_run(attrs)
      assert Enum.any?(Runs.list_runs(), &(&1.id == run.id))
    end

    test "get_run!/1 returns the run with given id", %{prompt_version: version} do
      attrs = Map.put(@valid_attrs, :prompt_version_id, version.id)
      {:ok, run} = Runs.create_run(attrs)
      assert Runs.get_run!(run.id).id == run.id
    end

    test "get_run!/1 preloads run_results and providers", %{
      prompt_version: version
    } do
      attrs = Map.put(@valid_attrs, :prompt_version_id, version.id)
      {:ok, run} = Runs.create_run(attrs)
      provider = provider_fixture()

      {:ok, _result} =
        Runs.create_run_result(%{
          run_id: run.id,
          provider_id: provider.id,
          output: "Hello Alice",
          input_tokens: 10,
          output_tokens: 5,
          latency_ms: 500,
          cost_usd: 0.001,
          status: :completed
        })

      loaded_run = Runs.get_run!(run.id)
      assert Ecto.assoc_loaded?(loaded_run.run_results)
      assert length(loaded_run.run_results) == 1
      assert Ecto.assoc_loaded?(hd(loaded_run.run_results).provider)
    end

    test "create_run/1 with valid data creates a run", %{
      prompt_version: version
    } do
      attrs = Map.put(@valid_attrs, :prompt_version_id, version.id)
      assert {:ok, %Run{} = run} = Runs.create_run(attrs)
      assert run.name == "Test Run"
      assert run.variable_values == %{"user" => "Alice", "topic" => "AI"}
      assert run.prompt_version_id == version.id
      assert run.status == :pending
      assert is_nil(run.started_at)
      assert is_nil(run.completed_at)
      assert is_nil(run.error_summary)
    end

    test "create_run/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Runs.create_run(@invalid_attrs)
    end

    test "update_run/2 with valid data updates the run", %{
      prompt_version: version
    } do
      attrs = Map.put(@valid_attrs, :prompt_version_id, version.id)
      {:ok, run} = Runs.create_run(attrs)
      assert {:ok, %Run{} = run} = Runs.update_run(run, @update_attrs)
      assert run.name == "Updated Run"
      assert run.variable_values == %{"user" => "Bob", "topic" => "ML"}
    end

    test "update_run/2 with invalid data returns error changeset", %{
      prompt_version: version
    } do
      attrs = Map.put(@valid_attrs, :prompt_version_id, version.id)
      {:ok, run} = Runs.create_run(attrs)

      assert {:error, %Ecto.Changeset{}} =
               Runs.update_run(run, @invalid_attrs)

      assert run.id == Runs.get_run!(run.id).id
    end

    test "delete_run/1 deletes the run", %{prompt_version: version} do
      attrs = Map.put(@valid_attrs, :prompt_version_id, version.id)
      {:ok, run} = Runs.create_run(attrs)
      assert {:ok, %Run{}} = Runs.delete_run(run)
      assert_raise Ecto.NoResultsError, fn -> Runs.get_run!(run.id) end
    end

    test "change_run/1 returns a run changeset", %{prompt_version: version} do
      attrs = Map.put(@valid_attrs, :prompt_version_id, version.id)
      {:ok, run} = Runs.create_run(attrs)
      assert %Ecto.Changeset{} = Runs.change_run(run)
    end

    test "change_run/2 returns a run changeset with attrs", %{
      prompt_version: version
    } do
      attrs = Map.put(@valid_attrs, :prompt_version_id, version.id)
      {:ok, run} = Runs.create_run(attrs)
      changeset = Runs.change_run(run, @update_attrs)
      assert %Ecto.Changeset{} = changeset
      assert changeset.changes.name == "Updated Run"
    end
  end

  describe "run_results" do
    @valid_result_attrs %{
      output: "Hello world",
      input_tokens: 10,
      output_tokens: 5,
      latency_ms: 500,
      cost_usd: 0.001,
      status: :completed
    }
    @update_result_attrs %{
      output: "Updated output",
      input_tokens: 15,
      output_tokens: 10,
      latency_ms: 750,
      cost_usd: 0.002,
      status: :error,
      error: "API error"
    }
    @invalid_result_attrs %{run_id: nil, provider_id: nil}

    setup do
      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Hello {{user}}")

      {:ok, run} =
        Runs.create_run(%{
          prompt_version_id: version.id,
          variable_values: %{"user" => "Test"}
        })

      provider = provider_fixture()
      {:ok, run: run, provider: provider}
    end

    test "create_run_result/1 with valid data creates a run_result", %{
      run: run,
      provider: provider
    } do
      attrs =
        @valid_result_attrs
        |> Map.put(:run_id, run.id)
        |> Map.put(:provider_id, provider.id)

      assert {:ok, %RunResult{} = result} = Runs.create_run_result(attrs)
      assert result.output == "Hello world"
      assert result.input_tokens == 10
      assert result.output_tokens == 5
      assert result.latency_ms == 500
      assert result.cost_usd == 0.001
      assert result.status == :completed
    end

    test "create_run_result/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} =
               Runs.create_run_result(@invalid_result_attrs)
    end

    test "update_run_result/2 with valid data updates the run_result", %{
      run: run,
      provider: provider
    } do
      attrs =
        @valid_result_attrs
        |> Map.put(:run_id, run.id)
        |> Map.put(:provider_id, provider.id)

      {:ok, result} = Runs.create_run_result(attrs)

      assert {:ok, %RunResult{} = result} =
               Runs.update_run_result(result, @update_result_attrs)

      assert result.output == "Updated output"
      assert result.input_tokens == 15
      assert result.status == :error
      assert result.error == "API error"
    end

    test "get_run_result!/1 preloads the provider", %{
      run: run,
      provider: provider
    } do
      attrs =
        @valid_result_attrs
        |> Map.put(:run_id, run.id)
        |> Map.put(:provider_id, provider.id)

      {:ok, result} = Runs.create_run_result(attrs)

      loaded_result = Runs.get_run_result!(result.id)

      assert loaded_result.id == result.id
      assert Ecto.assoc_loaded?(loaded_result.provider)
      assert loaded_result.provider.id == provider.id
    end

    test "update_run_result/2 with invalid data returns error changeset", %{
      run: run,
      provider: provider
    } do
      attrs =
        @valid_result_attrs
        |> Map.put(:run_id, run.id)
        |> Map.put(:provider_id, provider.id)

      {:ok, result} = Runs.create_run_result(attrs)

      assert {:error, %Ecto.Changeset{}} =
               Runs.update_run_result(result, @invalid_result_attrs)
    end
  end

  describe "execute_run/2" do
    setup do
      prompt = prompt_fixture()

      {:ok, version} =
        Aludel.Prompts.create_prompt_version(prompt, "Hello {{user}}")

      {:ok, run} =
        Runs.create_run(%{
          prompt_version_id: version.id,
          variable_values: %{"user" => "Alice"}
        })

      provider = provider_fixture()
      {:ok, run: run, provider: provider, prompt_version: version}
    end

    test "executes run with single provider", %{
      run: run,
      provider: provider
    } do
      mock_response = build_mock_response("Hello Alice", 5, 10)

      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      run = Repo.preload(run, :prompt_version)
      assert {:ok, %Execution{} = execution} = Runs.execute_run(run, [provider])
      assert execution.status == :ok

      assert execution.run.status == :completed
      assert execution.run.started_at
      assert execution.run.completed_at
      assert is_nil(execution.run.error_summary)
      assert Ecto.assoc_loaded?(execution.run.run_results)
      assert length(execution.run.run_results) == 1

      result = hd(execution.run.run_results)
      assert result.provider_id == provider.id
      assert result.status == :completed
      assert result.started_at
      assert result.completed_at
      assert is_binary(result.output)
      assert result.input_tokens > 0
      assert result.output_tokens > 0
      assert result.latency_ms >= 0
      assert result.artifacts["schema_version"] == 1
      assert [%{"status" => "completed"}] = result.artifacts["steps"]
    end

    test "executes run with multiple providers concurrently", %{
      run: run,
      provider: provider1
    } do
      mock_response = build_mock_response("Test response", 5, 10)

      # Use stub instead of expect for concurrent processes
      stub(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      provider2 = provider_fixture(%{name: "Provider 2"})
      provider3 = provider_fixture(%{name: "Provider 3"})

      run = Repo.preload(run, :prompt_version)

      assert {:ok, %Execution{} = execution} =
               Runs.execute_run(run, [provider1, provider2, provider3])

      assert execution.status == :ok
      assert execution.run.status == :completed
      assert execution.run.started_at
      assert execution.run.completed_at

      assert Ecto.assoc_loaded?(execution.run.run_results)
      assert length(execution.run.run_results) == 3

      provider_ids =
        Enum.map(execution.run.run_results, & &1.provider_id) |> Enum.sort()

      expected_ids = [provider1.id, provider2.id, provider3.id] |> Enum.sort()
      assert provider_ids == expected_ids

      for result <- execution.run.run_results do
        assert result.status == :completed
        assert result.started_at
        assert result.completed_at
        assert is_binary(result.output)
      end
    end

    test "broadcasts PubSub updates during execution", %{
      run: run,
      provider: provider
    } do
      mock_response = build_mock_response("Test response", 5, 10)

      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      Phoenix.PubSub.subscribe(Aludel.PubSub, "run:#{run.id}")

      run = Repo.preload(run, :prompt_version)
      assert {:ok, %Execution{status: :ok}} = Runs.execute_run(run, [provider])

      # Should receive at least one update message
      assert_receive {:run_result_update, _result_id, :completed, _output},
                     1000
    end

    test "renders template with variable values", %{
      run: run,
      provider: provider
    } do
      mock_response = build_mock_response("Hello Alice", 5, 10)

      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      run = Repo.preload(run, :prompt_version)
      assert {:ok, %Execution{} = execution} = Runs.execute_run(run, [provider])

      result = hd(execution.run.run_results)
      # The rendered prompt should contain "Hello Alice"
      assert result.output =~ "Hello Alice"
    end

    test "marks execution as fully failed when every provider fails", %{prompt_version: version} do
      provider = provider_fixture(%{name: "Error Provider"})

      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:error, "API timeout"}
      end)

      {:ok, run} =
        Runs.create_run(%{
          prompt_version_id: version.id,
          variable_values: %{"user" => "Test"}
        })

      run = Repo.preload(run, :prompt_version)

      assert {:ok, %Execution{} = execution} = Runs.execute_run(run, [provider])
      assert execution.status == :error
      assert length(execution.failures) == 1
      assert length(execution.run.run_results) == 1
      assert execution.run.status == :failed
      assert execution.run.started_at
      assert execution.run.completed_at
      assert execution.run.error_summary =~ provider.name
      assert hd(execution.run.run_results).status == :error
      assert hd(execution.run.run_results).started_at
      assert hd(execution.run.run_results).completed_at
      assert hd(execution.run.run_results).artifacts["schema_version"] == 1

      assert [%{"status" => "failed", "error" => %{"type" => "network_error"}}] =
               hd(execution.run.run_results).artifacts["steps"]
    end

    test "marks execution as partially failed when some providers fail", %{run: run} do
      provider1 = provider_fixture(%{name: "Provider 1", model: "provider-1-model"})
      provider2 = provider_fixture(%{name: "Provider 2", model: "provider-2-model"})

      expect(HttpClientMock, :request, 2, fn provider_model, _prompt, _opts ->
        case provider_model do
          "openai:provider-1-model" -> {:ok, build_mock_response("Test response", 5, 10)}
          "openai:provider-2-model" -> {:error, "API timeout"}
        end
      end)

      run = Repo.preload(run, :prompt_version)

      assert {:ok, %Execution{} = execution} = Runs.execute_run(run, [provider1, provider2])
      assert execution.status == :partial_failure
      assert length(execution.failures) == 1
      assert length(execution.run.run_results) == 2
      assert execution.run.status == :partial_failure
      assert execution.run.started_at
      assert execution.run.completed_at
      assert execution.run.error_summary =~ provider2.name
    end

    test "returns run_not_found when the run disappears before execution starts", %{
      run: run,
      provider: provider
    } do
      run = Repo.preload(run, :prompt_version)

      # Delete the run before execution can transition it to :running.
      Runs.delete_run(run)

      assert {:error, :run_not_found} = Runs.execute_run(run, [provider])
    end
  end

  describe "launch_run/2" do
    setup do
      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Hello {{user}}")

      {:ok, run} =
        Runs.create_run(%{
          prompt_version_id: version.id,
          variable_values: %{"user" => "Alice"}
        })

      provider = provider_fixture()

      {:ok, run: Repo.preload(run, :prompt_version), provider: provider}
    end

    test "starts execution under supervision and persists results", %{
      run: run,
      provider: provider
    } do
      test_pid = self()
      mock_response = build_mock_response("Hello Alice", 5, 10)

      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        send(test_pid, :llm_called)

        receive do
          :continue -> {:ok, mock_response}
        after
          1000 -> flunk("timed out waiting to continue executor task")
        end
      end)

      Phoenix.PubSub.subscribe(Aludel.PubSub, "run:#{run.id}")

      assert {:ok, pid} = Runs.launch_run(run, [provider])
      assert_receive :llm_called, 1000
      assert Process.alive?(pid)

      send(pid, :continue)

      assert_receive {:run_result_update, _result_id, :completed, "Hello Alice"}, 1000

      launched_run = Runs.get_run!(run.id)
      assert length(launched_run.run_results) == 1
      assert hd(launched_run.run_results).status == :completed
    end
  end

  defp build_mock_response(text, input_tokens, output_tokens) do
    %{
      content: text,
      input_tokens: input_tokens,
      output_tokens: output_tokens
    }
  end
end
