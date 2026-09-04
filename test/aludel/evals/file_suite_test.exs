defmodule Aludel.Evals.FileSuiteTest do
  use Aludel.DataCase, async: false

  import Aludel.EvalsFixtures
  import Aludel.PromptsFixtures
  import Aludel.ProvidersFixtures
  import Mox

  alias Aludel.Evals.FileSuite
  alias Aludel.Interfaces.HttpClientMock
  alias Aludel.Prompts

  describe "load_string/2" do
    test "loads equivalent JSON and YAML manifests with default sampling" do
      ids = manifest_ids()

      json =
        Jason.encode!(%{
          "schema_version" => 1,
          "suite_id" => ids.suite_id,
          "prompt_version_id" => ids.prompt_version_id,
          "provider_id" => ids.provider_id
        })

      yaml = """
      schema_version: 1
      suite_id: #{ids.suite_id}
      prompt_version_id: #{ids.prompt_version_id}
      provider_id: #{ids.provider_id}
      """

      assert {:ok, json_suite} = FileSuite.load_string(json, :json)
      assert {:ok, yaml_suite} = FileSuite.load_string(yaml, :yaml)
      assert json_suite == yaml_suite
      assert json_suite.sampling.samples == 1
      assert json_suite.sampling.reducer == :all
    end

    test "loads every supported sampling reducer" do
      ids = manifest_ids()

      for {reducer, minimum, expected} <- [
            {"all", nil, :all},
            {"any", nil, :any},
            {"majority", nil, :majority},
            {"minimum_pass_rate", 0.8, :minimum_pass_rate}
          ] do
        sampling =
          %{"samples" => 5, "reducer" => reducer}
          |> maybe_put("minimum_pass_rate", minimum)

        manifest = valid_manifest(ids, %{"sampling" => sampling})

        assert {:ok, file_suite} =
                 manifest
                 |> Jason.encode!()
                 |> FileSuite.load_string(:json)

        assert file_suite.sampling.samples == 5
        assert file_suite.sampling.reducer == expected
        assert file_suite.sampling.minimum_pass_rate == minimum
      end
    end

    test "treats an empty YAML sampling object like an empty JSON object" do
      ids = manifest_ids()

      yaml = """
      schema_version: 1
      suite_id: #{ids.suite_id}
      prompt_version_id: #{ids.prompt_version_id}
      provider_id: #{ids.provider_id}
      sampling: {}
      """

      assert {:ok, file_suite} = FileSuite.load_string(yaml, :yaml)
      assert file_suite.sampling.samples == 1
      assert file_suite.sampling.reducer == :all
    end

    test "rejects unsupported schemas, unknown fields, and malformed identifiers" do
      ids = manifest_ids()

      for {change, code} <- [
            {%{"schema_version" => 2}, "unsupported_schema"},
            {%{"extra" => true}, "invalid_manifest"},
            {%{"suite_id" => "not-a-uuid"}, "invalid_manifest"}
          ] do
        payload = ids |> valid_manifest(change) |> Jason.encode!()

        assert {:error, %{code: ^code, message: message}} =
                 FileSuite.load_string(payload, :json)

        assert is_binary(message)
      end
    end

    test "rejects duplicate mapping keys in JSON and YAML" do
      ids = manifest_ids()

      json =
        ~s({"schema_version":1,"schema_version":1,"suite_id":"#{ids.suite_id}",) <>
          ~s("prompt_version_id":"#{ids.prompt_version_id}","provider_id":"#{ids.provider_id}"})

      yaml = """
      schema_version: 1
      schema_version: 1
      suite_id: #{ids.suite_id}
      prompt_version_id: #{ids.prompt_version_id}
      provider_id: #{ids.provider_id}
      """

      for {payload, format} <- [{json, :json}, {yaml, :yaml}] do
        assert {:error, %{code: "invalid_manifest", message: message}} =
                 FileSuite.load_string(payload, format)

        assert message =~ "duplicate"
      end
    end

    test "rejects YAML aliases, explicit tags, and multiple documents" do
      ids = manifest_ids()

      alias_yaml = """
      schema_version: &version 1
      suite_id: #{ids.suite_id}
      prompt_version_id: #{ids.prompt_version_id}
      provider_id: #{ids.provider_id}
      sampling:
        samples: *version
      """

      multiple_documents = """
      schema_version: 1
      ---
      schema_version: 1
      """

      explicit_tag = """
      schema_version: !!int 1
      suite_id: #{ids.suite_id}
      prompt_version_id: #{ids.prompt_version_id}
      provider_id: #{ids.provider_id}
      """

      for {payload, expected_message} <- [
            {alias_yaml, "YAML aliases are not supported"},
            {explicit_tag, "explicit YAML tags are not supported"},
            {multiple_documents, "manifest must contain one YAML document"}
          ] do
        assert {:error, %{code: "invalid_manifest", message: ^expected_message}} =
                 FileSuite.load_string(payload, :yaml)
      end
    end

    test "rejects invalid and unbounded input before parsing" do
      assert {:error, %{code: "invalid_manifest"}} =
               FileSuite.load_string(<<255>>, :json)

      assert {:error, %{code: "manifest_too_large"}} =
               FileSuite.load_string(String.duplicate(" ", 262_145), :yaml)

      assert {:error, %{code: "unsupported_format"}} =
               FileSuite.load_string("{}", :toml)
    end
  end

  describe "load/1" do
    test "loads supported files and rejects other extensions" do
      ids = manifest_ids()
      directory = Path.join(System.tmp_dir!(), "aludel-file-suite-#{System.unique_integer()}")
      File.mkdir_p!(directory)

      on_exit(fn -> File.rm_rf(directory) end)

      path = Path.join(directory, "suite.json")
      File.write!(path, Jason.encode!(valid_manifest(ids)))

      assert {:ok, %FileSuite{suite_id: suite_id}} = FileSuite.load(path)
      assert suite_id == ids.suite_id

      assert {:error, %{code: "unsupported_format"}} =
               FileSuite.load(Path.join(directory, "suite.toml"))
    end
  end

  describe "load_and_execute/1" do
    test "executes the persisted suite without changing its test cases" do
      prompt = prompt_fixture()
      {:ok, prompt_version} = Prompts.create_prompt_version(prompt, "Hello {{name}}")
      suite = suite_fixture(%{prompt_id: prompt.id})
      provider = provider_fixture()

      test_case =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"name" => "Alice"},
          assertions: [%{"type" => "contains", "value" => "Hello"}]
        })

      expect(HttpClientMock, :request, 3, fn _model, _prompt, _options ->
        {:ok, %{content: "Hello Alice", input_tokens: 5, output_tokens: 3}}
      end)

      path = Path.join(System.tmp_dir!(), "aludel-file-suite-#{System.unique_integer()}.yaml")

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

      assert {:ok, suite_run} = FileSuite.load_and_execute(path)
      assert suite_run.suite_id == suite.id
      assert [%{"test_case_id" => test_case_id, "sampling" => sampling}] = suite_run.results
      assert test_case_id == test_case.id
      assert sampling["samples"] == 3
      assert length(Aludel.Evals.get_suite_with_test_cases!(suite.id).test_cases) == 1
    end

    test "rejects a prompt version owned by another prompt before execution" do
      suite = suite_fixture()
      other_prompt = prompt_fixture()
      {:ok, prompt_version} = Prompts.create_prompt_version(other_prompt, "Other")
      provider = provider_fixture()

      manifest =
        valid_manifest(%{
          suite_id: suite.id,
          prompt_version_id: prompt_version.id,
          provider_id: provider.id
        })

      assert {:ok, file_suite} = FileSuite.load_string(Jason.encode!(manifest), :json)

      assert {:error, %{code: "prompt_version_mismatch"}} =
               FileSuite.execute(file_suite)
    end

    test "rejects a manually forged manifest before database access" do
      file_suite = %FileSuite{
        schema_version: 2,
        suite_id: Ecto.UUID.generate(),
        prompt_version_id: Ecto.UUID.generate(),
        provider_id: Ecto.UUID.generate(),
        sampling: %Aludel.Evals.Sampling{samples: 0, reducer: :all}
      }

      assert {:error, %{code: "invalid_manifest"}} = FileSuite.execute(file_suite)
    end
  end

  defp manifest_ids do
    %{
      suite_id: Ecto.UUID.generate(),
      prompt_version_id: Ecto.UUID.generate(),
      provider_id: Ecto.UUID.generate()
    }
  end

  defp valid_manifest(ids, overrides \\ %{}) do
    Map.merge(
      %{
        "schema_version" => 1,
        "suite_id" => ids.suite_id,
        "prompt_version_id" => ids.prompt_version_id,
        "provider_id" => ids.provider_id
      },
      overrides
    )
  end

  defp maybe_put(map, _key, nil) do
    map
  end

  defp maybe_put(map, key, value) do
    Map.put(map, key, value)
  end
end
