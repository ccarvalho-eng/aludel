defmodule Aludel.ExecutionTest do
  use Aludel.DataCase

  import Mox

  alias Aludel.Execution
  alias Aludel.Interfaces.HttpClientMock

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    original_mode = Application.get_env(:aludel, :execution_mode)
    original_executor = Application.get_env(:aludel, :executor)

    on_exit(fn ->
      Application.put_env(:aludel, :execution_mode, original_mode)
      Application.put_env(:aludel, :executor, original_executor)
    end)

    :ok
  end

  test "delegates native execution to the llm client" do
    Application.put_env(:aludel, :execution_mode, :native)

    prompt = prompt_fixture()
    {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Hello {{name}}")
    provider = provider_fixture(%{provider: :openai, model: "gpt-4o-mini"})

    expect(HttpClientMock, :request, fn "openai:gpt-4o-mini", "Hello Alice", opts ->
      assert Keyword.get(opts, :api_key) == "sk-test-fake-openai-key-for-testing"
      {:ok, %{content: "Hello Alice", input_tokens: 5, output_tokens: 7}}
    end)

    assert {:ok, result} =
             Execution.execute(%{
               kind: :run,
               prompt_version: version,
               variables: %{"name" => "Alice"},
               provider: provider,
               documents: [],
               metadata: %{run_id: Ecto.UUID.generate()}
             })

    assert result.output == "Hello Alice"
    assert result.input_tokens == 5
    assert result.output_tokens == 7
    assert is_integer(result.latency_ms)
    assert is_float(result.cost_usd)
    assert result.metadata == nil
  end

  test "captures a normalized native artifact without provider configuration" do
    Application.put_env(:aludel, :execution_mode, :native)

    prompt = prompt_fixture()
    {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Return JSON for {{name}}")

    provider =
      provider_fixture(%{
        provider: :openai,
        model: "gpt-4o-mini",
        config: %{"api_key" => "must-not-be-persisted"}
      })

    expect(HttpClientMock, :request, fn _model, "Return JSON for Alice", _opts ->
      {:ok, %{content: ~s({"name":"Alice"}), input_tokens: 5, output_tokens: 7}}
    end)

    assert {:ok, result} =
             Execution.execute_with_artifacts(%{
               kind: :run,
               prompt_version: version,
               variables: %{"name" => "Alice"},
               provider: provider,
               documents: [],
               metadata: %{run_id: Ecto.UUID.generate()}
             })

    assert result.artifacts["schema_version"] == 1
    assert [step] = result.artifacts["steps"]
    assert step["index"] == 0
    assert step["mode"] == "native"
    assert step["status"] == "completed"
    assert step["input"]["rendered_prompt"] == "Return JSON for Alice"

    assert step["input"]["provider"] == %{
             "id" => provider.id,
             "model" => "gpt-4o-mini",
             "type" => "openai"
           }

    assert step["output"]["parsed"] == %{"name" => "Alice"}
    assert step["output"]["raw"] == ~s({"name":"Alice"})
    refute inspect(result.artifacts) =~ "must-not-be-persisted"
    refute inspect(result.artifacts) =~ "config"
  end

  test "captures structured failure artifacts while preserving execute/1 compatibility" do
    Application.put_env(:aludel, :execution_mode, :native)

    prompt = prompt_fixture()
    {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Hello {{name}}")
    provider = provider_fixture()

    expect(HttpClientMock, :request, 2, fn _model, _prompt, _opts ->
      {:error, "API timeout"}
    end)

    request = %{
      kind: :run,
      prompt_version: version,
      variables: %{"name" => "Alice"},
      provider: provider,
      documents: [],
      metadata: %{run_id: Ecto.UUID.generate()}
    }

    assert {:error, {:network_error, "API timeout"}, artifacts} =
             Execution.execute_with_artifacts(request)

    assert %{
             "schema_version" => 1,
             "steps" => [
               %{
                 "error" => %{"type" => "network_error"},
                 "status" => "failed"
               }
             ]
           } = artifacts

    assert {:error, {:network_error, "API timeout"}} = Execution.execute(request)
  end

  test "returns a structured error when callback mode is missing an executor" do
    Application.put_env(:aludel, :execution_mode, :callback)
    Application.delete_env(:aludel, :executor)

    prompt = prompt_fixture()
    {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Hello {{name}}")
    provider = provider_fixture()

    assert {:error, :executor_not_configured} =
             Execution.execute(%{
               kind: :run,
               prompt_version: version,
               variables: %{"name" => "Alice"},
               provider: provider,
               documents: [],
               metadata: %{run_id: Ecto.UUID.generate()}
             })
  end

  test "returns a structured error when execution mode config is invalid" do
    Application.put_env(:aludel, :execution_mode, :calback)

    prompt = prompt_fixture()
    {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Hello {{name}}")
    provider = provider_fixture()

    assert {:error, {:invalid_execution_mode, :calback}} =
             Execution.execute(%{
               kind: :run,
               prompt_version: version,
               variables: %{"name" => "Alice"},
               provider: provider,
               documents: [],
               metadata: %{run_id: Ecto.UUID.generate()}
             })
  end

  test "normalizes callback raises into structured errors" do
    Application.put_env(:aludel, :execution_mode, :callback)
    Application.put_env(:aludel, :executor, Aludel.ExecutorMock)

    prompt = prompt_fixture()
    {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Hello {{name}}")
    provider = provider_fixture()

    expect(Aludel.ExecutorMock, :run, fn _input ->
      raise "boom"
    end)

    assert {:error, {:executor_crash, {:raise, %RuntimeError{message: "boom"}}}} =
             Execution.execute(%{
               kind: :run,
               prompt_version: version,
               variables: %{"name" => "Alice"},
               provider: provider,
               documents: [],
               metadata: %{run_id: Ecto.UUID.generate()}
             })
  end

  test "normalizes callback exits into structured errors" do
    Application.put_env(:aludel, :execution_mode, :callback)
    Application.put_env(:aludel, :executor, Aludel.ExecutorMock)

    prompt = prompt_fixture()
    {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Hello {{name}}")
    provider = provider_fixture()

    expect(Aludel.ExecutorMock, :run, fn _input ->
      exit(:boom)
    end)

    assert {:error, {:executor_crash, {:exit, :boom}}} =
             Execution.execute(%{
               kind: :run,
               prompt_version: version,
               variables: %{"name" => "Alice"},
               provider: provider,
               documents: [],
               metadata: %{run_id: Ecto.UUID.generate()}
             })
  end

  test "rejects callback metadata that is not JSON-encodable" do
    Application.put_env(:aludel, :execution_mode, :callback)
    Application.put_env(:aludel, :executor, Aludel.ExecutorMock)

    prompt = prompt_fixture()
    {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Hello {{name}}")
    provider = provider_fixture()

    expect(Aludel.ExecutorMock, :run, fn _input ->
      {:ok,
       %{
         output: "Hello Alice",
         metadata: %{pid: self()}
       }}
    end)

    assert {:error, {:invalid_executor_response, :invalid_metadata}} =
             Execution.execute(%{
               kind: :run,
               prompt_version: version,
               variables: %{"name" => "Alice"},
               provider: provider,
               documents: [],
               metadata: %{run_id: Ecto.UUID.generate()}
             })
  end

  test "loads suite documents and normalizes callback responses" do
    Application.put_env(:aludel, :execution_mode, :callback)
    Application.put_env(:aludel, :executor, Aludel.ExecutorMock)

    prompt = prompt_fixture()
    {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Ignored {{name}}")
    provider = provider_fixture(%{provider: :openai, model: "gpt-4.1"})
    suite = suite_fixture(%{prompt_id: prompt.id})
    test_case = test_case_fixture(%{suite_id: suite.id, variable_values: %{"name" => "Alice"}})

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
      assert input.prompt_version.id == version.id
      assert input.provider.id == provider.id
      assert input.provider.provider == :openai
      assert input.provider.model == "gpt-4.1"
      assert input.metadata.suite_id == suite.id
      assert input.metadata.test_case_id == test_case.id
      assert [%{name: "policy.txt", content_type: "text/plain", data: data}] = input.documents
      assert data == "reset password instructions"

      {:ok,
       %{
         output: "Use the reset password page.",
         input_tokens: nil,
         output_tokens: 11,
         latency_ms: 1234,
         cost_usd: nil,
         metadata: %{"trace_id" => "trace-123"}
       }}
    end)

    assert {:ok, result} =
             Execution.execute(%{
               kind: :suite,
               prompt_version: version,
               variables: test_case.variable_values,
               provider: provider,
               documents: Aludel.Repo.get().preload(test_case, :documents).documents,
               metadata: %{suite_id: suite.id, test_case_id: test_case.id}
             })

    assert result.output == "Use the reset password page."
    assert result.input_tokens == nil
    assert result.output_tokens == 11
    assert result.latency_ms == 1234
    assert result.cost_usd == nil
    assert result.metadata == %{"trace_id" => "trace-123"}
    assert [%{"mode" => "callback", "input" => artifact_input}] = result.artifacts["steps"]
    assert artifact_input["prompt_version"]["template"] == "Ignored {{name}}"
    assert [%{"name" => "policy.txt", "size_bytes" => 27}] = artifact_input["documents"]
    refute inspect(result.artifacts) =~ "reset password instructions"
    refute inspect(result.artifacts) =~ "config"
  end
end
