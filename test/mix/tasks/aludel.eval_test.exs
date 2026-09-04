defmodule Mix.Tasks.Aludel.EvalTest do
  use Aludel.DataCase, async: false

  import Aludel.EvalsFixtures
  import Aludel.PromptsFixtures
  import Aludel.ProvidersFixtures
  import ExUnit.CaptureIO
  import Mox

  alias Aludel.Evals
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
    assert payload["schema_version"] == 2
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

  test "executes a versioned YAML suite manifest" do
    %{suite: suite, prompt_version: prompt_version, provider: provider} = evaluation_targets()

    expect(HttpClientMock, :request, 3, fn _model, _prompt, _options ->
      {:ok, %{content: "Hello Alice", input_tokens: 5, output_tokens: 3}}
    end)

    path = Path.join(System.tmp_dir!(), "aludel-eval-#{System.unique_integer()}.yaml")

    File.write!(path, """
    schema_version: 1
    suite_id: #{suite.id}
    prompt_version_id: #{prompt_version.id}
    provider_id: #{provider.id}
    sampling:
      samples: 3
      reducer: majority
    """)

    on_exit(fn -> File.rm(path) end)

    output =
      capture_io(fn ->
        EvalTask.run(["--file", path])
      end)

    payload = Jason.decode!(output)

    assert payload["status"] == "passed"
    assert payload["suite_id"] == suite.id
    assert [result] = payload["results"]
    assert result["input_tokens"] == 15
    assert result["output_tokens"] == 9
  end

  test "rejects combining a suite manifest with individual target flags" do
    %{suite: suite, prompt_version: prompt_version, provider: provider} = evaluation_targets()

    output =
      capture_io(fn ->
        assert_raise Mix.Error, "--file cannot be combined with target ID options", fn ->
          EvalTask.run(["--file", "suite.json"] ++ task_args(suite, prompt_version, provider))
        end
      end)

    assert Jason.decode!(output)["error"]["code"] == "invalid_arguments"
  end

  test "emits a stable error for an invalid suite manifest" do
    %{suite: suite, prompt_version: prompt_version, provider: provider} = evaluation_targets()
    path = Path.join(System.tmp_dir!(), "aludel-eval-#{System.unique_integer()}.json")

    File.write!(
      path,
      Jason.encode!(%{
        "schema_version" => 2,
        "suite_id" => suite.id,
        "prompt_version_id" => prompt_version.id,
        "provider_id" => provider.id
      })
    )

    on_exit(fn -> File.rm(path) end)

    output =
      capture_io(fn ->
        assert_raise Mix.Error, "schema_version must be 1", fn ->
          EvalTask.run(["--file", path])
        end
      end)

    assert Jason.decode!(output)["error"]["code"] == "unsupported_schema"
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

  test "uses a suite quality policy as the CI gate" do
    %{suite: suite, prompt_version: prompt_version, provider: provider} = evaluation_targets()

    assert {:ok, policy} =
             Evals.create_suite_policy(suite, %{
               "schema_version" => 1,
               "rules" => [
                 %{
                   "id" => "overall",
                   "type" => "overall_pass_rate",
                   "minimum" => 0.0
                 }
               ]
             })

    expect(HttpClientMock, :request, fn _model, _prompt, _options ->
      {:ok, %{content: "Goodbye", input_tokens: 4, output_tokens: 2}}
    end)

    output =
      capture_io(fn ->
        EvalTask.run(task_args(suite, prompt_version, provider))
      end)

    payload = Jason.decode!(output)

    assert payload["status"] == "passed"
    assert payload["summary"]["failed"] == 1
    assert payload["quality_policy"]["policy_id"] == policy.id
    assert payload["quality_policy"]["policy_version"] == 1
    assert payload["quality_policy"]["status"] == "passed"
  end

  test "fails with an explicit unavailable policy status" do
    %{suite: suite, prompt_version: prompt_version, provider: provider} = evaluation_targets()

    assert {:ok, _policy} =
             Evals.create_suite_policy(suite, %{
               "schema_version" => 1,
               "rules" => [
                 %{
                   "id" => "priority",
                   "type" => "metadata_pass_rate",
                   "metadata" => %{"priority" => "missing"},
                   "minimum" => 1.0
                 }
               ]
             })

    expect(HttpClientMock, :request, fn _model, _prompt, _options ->
      {:ok, %{content: "Hello Alice", input_tokens: 5, output_tokens: 3}}
    end)

    output =
      capture_io(fn ->
        assert_raise Mix.Error, "Evaluation did not pass", fn ->
          EvalTask.run(task_args(suite, prompt_version, provider))
        end
      end)

    payload = Jason.decode!(output)

    assert payload["status"] == "unavailable"
    assert payload["quality_policy"]["status"] == "unavailable"

    assert payload["quality_policy"]["rules"] |> hd() |> Map.fetch!("reason") =~
             "metadata"
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
             "schema_version" => 2,
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

  test "emits console, JUnit, and GitHub reports" do
    Enum.each(
      [
        {"console", "Aludel evaluation PASSED"},
        {"junit", ~s(<testsuites tests="1" failures="0")},
        {"github", "::notice title=Aludel evaluation::"}
      ],
      fn {format, expected} ->
        %{suite: suite, prompt_version: prompt_version, provider: provider} =
          evaluation_targets()

        expect(HttpClientMock, :request, fn _model, _prompt, _options ->
          {:ok, %{content: "Hello Alice", input_tokens: 5, output_tokens: 3}}
        end)

        output =
          capture_io(fn ->
            EvalTask.run(task_args(suite, prompt_version, provider) ++ ["--format", format])
          end)

        assert output =~ expected
      end
    )
  end

  test "includes generated responses in JUnit only when explicitly requested" do
    %{suite: suite, prompt_version: prompt_version, provider: provider} = evaluation_targets()

    expect(HttpClientMock, :request, fn _model, _prompt, _options ->
      {:ok, %{content: "Hello Alice", input_tokens: 5, output_tokens: 3}}
    end)

    output =
      capture_io(fn ->
        EvalTask.run(
          task_args(suite, prompt_version, provider) ++
            ["--format", "junit", "--include-output"]
        )
      end)

    assert output =~ "<system-out>Hello Alice</system-out>"
  end

  test "writes a report to the requested output path" do
    %{suite: suite, prompt_version: prompt_version, provider: provider} = evaluation_targets()
    output_path = Path.join(System.tmp_dir!(), "aludel-report-#{System.unique_integer()}.xml")

    on_exit(fn -> File.rm(output_path) end)

    expect(HttpClientMock, :request, fn _model, _prompt, _options ->
      {:ok, %{content: "Hello Alice", input_tokens: 5, output_tokens: 3}}
    end)

    assert capture_io(fn ->
             EvalTask.run(
               task_args(suite, prompt_version, provider) ++
                 ["--format", "junit", "--output", output_path]
             )
           end) == ""

    assert File.read!(output_path) =~ ~s(<testsuites tests="1" failures="0")
  end

  test "rejects an unsupported report format before execution" do
    %{suite: suite, prompt_version: prompt_version, provider: provider} = evaluation_targets()

    output =
      capture_io(fn ->
        assert_raise Mix.Error, "format must be one of: console, github, json, junit", fn ->
          EvalTask.run(task_args(suite, prompt_version, provider) ++ ["--format", "html"])
        end
      end)

    assert Jason.decode!(output)["error"]["code"] == "invalid_format"
  end

  test "rejects format-specific options on other reporters before execution" do
    %{suite: suite, prompt_version: prompt_version, provider: provider} = evaluation_targets()

    for {options, message} <- [
          {["--format", "console", "--pretty"], "--pretty requires --format json"},
          {["--format", "json", "--include-output"], "--include-output requires --format junit"}
        ] do
      output =
        capture_io(fn ->
          assert_raise Mix.Error, message, fn ->
            EvalTask.run(task_args(suite, prompt_version, provider) ++ options)
          end
        end)

      assert Jason.decode!(output)["error"]["code"] == "invalid_options"
    end
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
