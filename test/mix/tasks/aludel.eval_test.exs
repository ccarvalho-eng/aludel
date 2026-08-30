defmodule Mix.Tasks.Aludel.EvalTest do
  use Aludel.DataCase, async: false

  import Aludel.EvalsFixtures
  import Aludel.PromptsFixtures
  import Aludel.ProvidersFixtures
  import ExUnit.CaptureIO
  import Mox

  alias Aludel.Interfaces.HttpClientMock
  alias Aludel.Prompts
  alias Mix.Tasks.Aludel.Eval, as: EvalTask

  test "emits passing JSON for a successful suite run" do
    %{suite: suite, prompt_version: prompt_version, provider: provider} = evaluation_targets()

    expect(HttpClientMock, :request, fn _model, _prompt, _options ->
      {:ok, %{content: "Hello Alice", input_tokens: 5, output_tokens: 3}}
    end)

    output =
      capture_io(fn ->
        EvalTask.run(task_args(suite, prompt_version, provider))
      end)

    payload = Jason.decode!(output)

    assert payload["type"] == "aludel_eval"
    assert payload["schema_version"] == 1
    assert payload["status"] == "passed"
    assert payload["suite_id"] == suite.id
    assert payload["prompt_version_id"] == prompt_version.id
    assert payload["provider_id"] == provider.id
    assert payload["summary"]["passed"] == 1
    assert payload["summary"]["failed"] == 0
    assert payload["summary"]["pass_rate"] == 100.0

    assert [
             %{
               "status" => "passed",
               "passed" => true,
               "assertion_results" => [
                 %{
                   "reason" => "Output contains expected value",
                   "metadata" => %{}
                 }
               ]
             }
           ] = payload["results"]
  end

  test "emits failing JSON and raises when an assertion fails" do
    %{suite: suite, prompt_version: prompt_version, provider: provider} = evaluation_targets()

    expect(HttpClientMock, :request, fn _model, _prompt, _options ->
      {:ok, %{content: "Goodbye", input_tokens: 4, output_tokens: 2}}
    end)

    output =
      capture_io(fn ->
        assert_raise Mix.Error, "Evaluation did not pass", fn ->
          EvalTask.run(task_args(suite, prompt_version, provider))
        end
      end)

    payload = Jason.decode!(output)

    assert payload["status"] == "failed"
    assert payload["summary"]["passed"] == 0
    assert payload["summary"]["failed"] == 1
    assert [%{"status" => "failed", "passed" => false}] = payload["results"]
  end

  test "treats an empty suite as a failing evaluation" do
    prompt = prompt_fixture()
    {:ok, prompt_version} = Prompts.create_prompt_version(prompt, "Hello {{name}}")
    suite = suite_fixture(%{prompt_id: prompt.id})
    provider = provider_fixture()

    output =
      capture_io(fn ->
        assert_raise Mix.Error, "Evaluation did not pass", fn ->
          EvalTask.run(task_args(suite, prompt_version, provider))
        end
      end)

    payload = Jason.decode!(output)

    assert payload["status"] == "failed"
    assert payload["summary"]["total"] == 0
    assert payload["summary"]["pass_rate"] == 0.0
    assert payload["results"] == []
  end

  test "emits a JSON error for missing required options" do
    output =
      capture_io(fn ->
        assert_raise Mix.Error, ~r/Missing required options/, fn ->
          EvalTask.run([])
        end
      end)

    payload = Jason.decode!(output)

    assert payload == %{
             "type" => "aludel_eval",
             "schema_version" => 1,
             "status" => "error",
             "error" => %{
               "code" => "invalid_arguments",
               "message" =>
                 "Missing required options: --suite-id, --prompt-version-id, --provider-id"
             }
           }
  end

  test "rejects a prompt version from another prompt before execution" do
    %{suite: suite, provider: provider} = evaluation_targets()
    other_prompt = prompt_fixture()
    {:ok, other_version} = Prompts.create_prompt_version(other_prompt, "Other {{name}}")

    output =
      capture_io(fn ->
        assert_raise Mix.Error, "prompt_version does not belong to the suite prompt", fn ->
          EvalTask.run(task_args(suite, other_version, provider))
        end
      end)

    payload = Jason.decode!(output)

    assert payload["status"] == "error"
    assert payload["error"]["code"] == "prompt_version_mismatch"
  end

  defp evaluation_targets do
    prompt = prompt_fixture()
    {:ok, prompt_version} = Prompts.create_prompt_version(prompt, "Hello {{name}}")
    suite = suite_fixture(%{prompt_id: prompt.id})

    _test_case =
      test_case_fixture(%{
        suite_id: suite.id,
        variable_values: %{"name" => "Alice"},
        assertions: [%{"type" => "contains", "value" => "Hello"}]
      })

    %{suite: suite, prompt_version: prompt_version, provider: provider_fixture()}
  end

  defp task_args(suite, prompt_version, provider) do
    [
      "--suite-id",
      suite.id,
      "--prompt-version-id",
      prompt_version.id,
      "--provider-id",
      provider.id
    ]
  end
end
