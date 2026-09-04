defmodule Aludel.Evals.FileSuite do
  @moduledoc """
  Loads and executes versioned JSON or YAML suite manifests.

  A manifest identifies a persisted suite, prompt version, and provider. It may
  also define bounded repeated-sampling settings. Test cases and dataset
  provenance remain owned by the database; executing a manifest never imports,
  replaces, or deletes suite data.

  Schema version 1 accepts this shape:

      schema_version: 1
      suite_id: 9a756a58-eaec-43ca-99e6-f5c016d85d0c
      prompt_version_id: e74cf2e1-94b6-4bcb-9ed9-b259661be906
      provider_id: e1c60ec0-6d55-419b-b958-7d088055254f
      sampling:
        samples: 5
        reducer: majority

  Supported reducers are `all`, `any`, `majority`, and
  `minimum_pass_rate`. The latter also requires `minimum_pass_rate` between
  `0.0` and `1.0`.

  Files are limited to 256 KiB. Parsing rejects unsupported extensions,
  invalid UTF-8, aliases, explicit YAML tags, multiple YAML documents,
  duplicate mapping keys, unknown fields, and unsupported schema versions
  before database access.
  """

  alias Aludel.Evals
  alias Aludel.Evals.{Sampling, Suite, SuiteRun}
  alias Aludel.Prompts
  alias Aludel.Prompts.PromptVersion
  alias Aludel.Providers
  alias Aludel.Providers.Provider

  @max_bytes 256 * 1024
  @max_yaml_tokens 200
  @schema_version 1
  @top_level_fields ~w(schema_version suite_id prompt_version_id provider_id sampling)
  @required_fields ~w(schema_version suite_id prompt_version_id provider_id)
  @sampling_fields ~w(samples reducer minimum_pass_rate)
  @simple_reducers ~w(all any majority)

  @enforce_keys [
    :schema_version,
    :suite_id,
    :prompt_version_id,
    :provider_id,
    :sampling
  ]
  defstruct @enforce_keys

  @type error :: %{code: String.t(), message: String.t()}
  @type format :: :json | :yaml
  @type t :: %__MODULE__{
          schema_version: 1,
          suite_id: Ecto.UUID.t(),
          prompt_version_id: Ecto.UUID.t(),
          provider_id: Ecto.UUID.t(),
          sampling: Sampling.t()
        }

  @doc """
  Loads and validates a `.json`, `.yaml`, or `.yml` manifest.

  The file is read with a fixed upper bound. Errors have stable `code` and
  `message` fields suitable for command-line and application handling.
  """
  @spec load(Path.t()) :: {:ok, t()} | {:error, error()}
  def load(path) when is_binary(path) do
    with {:ok, format} <- format_for_path(path),
         {:ok, contents} <- read_bounded(path) do
      load_string(contents, format)
    end
  end

  def load(_path) do
    error("invalid_path", "manifest path must be a string")
  end

  @doc """
  Parses and validates manifest content in `:json` or `:yaml` format.

  The same size, encoding, duplicate-key, schema, identifier, and sampling
  checks used by `load/1` apply to in-memory content.
  """
  @spec load_string(binary(), format()) :: {:ok, t()} | {:error, error()}
  def load_string(contents, format) when is_binary(contents) do
    with :ok <- validate_contents(contents),
         {:ok, decoded} <- decode(contents, format) do
      validate_manifest(decoded)
    end
  end

  def load_string(_contents, _format) do
    error("invalid_manifest", "manifest content must be a string")
  end

  @doc """
  Executes a validated manifest against its persisted suite.

  The prompt version must belong to the suite's prompt. The suite's existing
  test cases, document associations, and latest quality policy are used without
  modifying dataset ownership.
  """
  @spec execute(t()) :: {:ok, SuiteRun.t()} | {:error, error()}
  def execute(%__MODULE__{} = file_suite) do
    with {:ok, sampling} <- validate_sampling_struct(file_suite),
         {:ok, suite} <- fetch_suite(file_suite.suite_id),
         {:ok, prompt_version} <- fetch_prompt_version(file_suite.prompt_version_id),
         {:ok, provider} <- fetch_provider(file_suite.provider_id),
         :ok <- validate_prompt_version(suite, prompt_version) do
      execute_suite(suite, prompt_version, provider, sampling)
    end
  end

  @doc """
  Loads, validates, and executes a suite manifest.

  Invalid files and targets return stable errors instead of starting a partial
  evaluation.
  """
  @spec load_and_execute(Path.t()) :: {:ok, SuiteRun.t()} | {:error, error()}
  def load_and_execute(path) do
    with {:ok, file_suite} <- load(path) do
      execute(file_suite)
    end
  end

  defp format_for_path(path) do
    case path |> Path.extname() |> String.downcase() do
      ".json" -> {:ok, :json}
      ".yaml" -> {:ok, :yaml}
      ".yml" -> {:ok, :yaml}
      _extension -> error("unsupported_format", "manifest must use .json, .yaml, or .yml")
    end
  end

  defp read_bounded(path) do
    case File.open(path, [:read, :binary], fn device ->
           IO.binread(device, @max_bytes + 1)
         end) do
      {:ok, contents} when is_binary(contents) and byte_size(contents) <= @max_bytes ->
        {:ok, contents}

      {:ok, contents} when is_binary(contents) ->
        error("manifest_too_large", "manifest exceeds the 256 KiB limit")

      {:ok, :eof} ->
        {:ok, ""}

      {:ok, {:error, _reason}} ->
        error("file_unreadable", "manifest could not be read")

      {:error, _reason} ->
        error("file_unreadable", "manifest could not be read")
    end
  end

  defp validate_contents(contents) when byte_size(contents) > @max_bytes do
    error("manifest_too_large", "manifest exceeds the 256 KiB limit")
  end

  defp validate_contents(contents) do
    if String.valid?(contents) do
      :ok
    else
      error("invalid_manifest", "manifest must contain valid UTF-8")
    end
  end

  defp decode(contents, :json) do
    case Jason.decode(contents, objects: :ordered_objects) do
      {:ok, decoded} -> normalize_json(decoded)
      {:error, _reason} -> error("invalid_manifest", "manifest contains invalid JSON")
    end
  end

  defp decode(contents, :yaml) do
    with :ok <- validate_yaml_tokens(contents),
         {:ok, mappings} <- YamlElixir.read_from_string(contents, maps_as_keywords: true),
         {:ok, _normalized} <- normalize_yaml(mappings),
         {:ok, decoded} <- YamlElixir.read_from_string(contents) do
      {:ok, decoded}
    else
      {:error, %{code: _code, message: _message} = error} -> {:error, error}
      {:error, _reason} -> error("invalid_manifest", "manifest contains invalid YAML")
    end
  end

  defp decode(_contents, _format) do
    error("unsupported_format", "format must be :json or :yaml")
  end

  defp normalize_json(%Jason.OrderedObject{values: values}) do
    normalize_mapping(values, &normalize_json/1)
  end

  defp normalize_json(values) when is_list(values) do
    normalize_sequence(values, &normalize_json/1)
  end

  defp normalize_json(value) do
    {:ok, value}
  end

  defp normalize_yaml(values) when is_list(values) do
    if mapping_entries?(values) do
      normalize_mapping(values, &normalize_yaml/1)
    else
      normalize_sequence(values, &normalize_yaml/1)
    end
  end

  defp normalize_yaml(value) do
    {:ok, value}
  end

  defp normalize_mapping(entries, normalize_value) do
    keys = Enum.map(entries, &elem(&1, 0))

    if length(keys) == MapSet.size(MapSet.new(keys)) do
      normalize_entries(entries, normalize_value)
    else
      error("invalid_manifest", "manifest contains duplicate mapping keys")
    end
  end

  defp normalize_entries(entries, normalize_value) do
    Enum.reduce_while(entries, {:ok, %{}}, fn {key, value}, {:ok, normalized} ->
      normalize_mapping_entry(key, value, normalized, normalize_value)
    end)
  end

  defp normalize_mapping_entry(key, value, normalized, normalize_value) do
    case normalize_value.(value) do
      {:ok, normalized_value} ->
        {:cont, {:ok, Map.put(normalized, key, normalized_value)}}

      {:error, _error} = error ->
        {:halt, error}
    end
  end

  defp normalize_sequence(values, normalize_value) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, normalized} ->
      case normalize_value.(value) do
        {:ok, normalized_value} -> {:cont, {:ok, [normalized_value | normalized]}}
        {:error, _error} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      {:error, _error} = error -> error
    end
  end

  defp mapping_entries?([]) do
    false
  end

  defp mapping_entries?(values) do
    Enum.all?(values, &(is_tuple(&1) and tuple_size(&1) == 2))
  end

  defp validate_yaml_tokens(contents) do
    :yamerl_parser.string(contents, token_fun: yaml_token_fun(0, 0))
    :ok
  catch
    :throw, :yaml_alias ->
      error("invalid_manifest", "YAML aliases are not supported")

    :throw, :multiple_yaml_documents ->
      error("invalid_manifest", "manifest must contain one YAML document")

    :throw, :too_many_yaml_tokens ->
      error("invalid_manifest", "manifest structure is too complex")

    :throw, :explicit_yaml_tag ->
      error("invalid_manifest", "explicit YAML tags are not supported")

    _kind, _reason ->
      error("invalid_manifest", "manifest contains invalid YAML")
  end

  defp yaml_token_fun(document_count, token_count) do
    fn token ->
      token_type = elem(token, 0)

      cond do
        token_count >= @max_yaml_tokens ->
          throw(:too_many_yaml_tokens)

        token_type in [:yamerl_alias, :yamerl_anchor] ->
          throw(:yaml_alias)

        explicit_yaml_tag_token?(token) ->
          throw(:explicit_yaml_tag)

        token_type == :yamerl_doc_start and document_count > 0 ->
          throw(:multiple_yaml_documents)

        token_type == :yamerl_doc_start ->
          {:ok, yaml_token_fun(document_count + 1, token_count + 1)}

        true ->
          {:ok, yaml_token_fun(document_count, token_count + 1)}
      end
    end
  end

  defp explicit_yaml_tag_token?({
         :yamerl_scalar,
         _line,
         _column,
         tag,
         _style,
         _substyle,
         _text
       }) do
    explicit_yaml_tag?(tag)
  end

  defp explicit_yaml_tag_token?({
         :yamerl_collection_start,
         _line,
         _column,
         tag,
         _style,
         _kind
       }) do
    explicit_yaml_tag?(tag)
  end

  defp explicit_yaml_tag_token?(_token) do
    false
  end

  defp explicit_yaml_tag?({:yamerl_tag, _line, _column, {:non_specific, _name}}) do
    false
  end

  defp explicit_yaml_tag?({:yamerl_tag, _line, _column, _name}) do
    true
  end

  defp validate_manifest(manifest) when is_map(manifest) do
    with :ok <- validate_fields(manifest, @top_level_fields, @required_fields, "manifest"),
         :ok <- validate_schema_version(manifest["schema_version"]),
         {:ok, suite_id} <- validate_id(manifest["suite_id"], "suite_id"),
         {:ok, prompt_version_id} <-
           validate_id(manifest["prompt_version_id"], "prompt_version_id"),
         {:ok, provider_id} <- validate_id(manifest["provider_id"], "provider_id"),
         {:ok, sampling} <- validate_sampling(Map.get(manifest, "sampling")) do
      {:ok,
       %__MODULE__{
         schema_version: @schema_version,
         suite_id: suite_id,
         prompt_version_id: prompt_version_id,
         provider_id: provider_id,
         sampling: sampling
       }}
    end
  end

  defp validate_manifest(_manifest) do
    error("invalid_manifest", "manifest root must be an object")
  end

  defp validate_fields(value, allowed, required, name) do
    unknown = Map.keys(value) -- allowed
    missing = required -- Map.keys(value)

    cond do
      unknown != [] -> error("invalid_manifest", "#{name} contains unknown fields")
      missing != [] -> error("invalid_manifest", "#{name} is missing required fields")
      true -> :ok
    end
  end

  defp validate_schema_version(@schema_version) do
    :ok
  end

  defp validate_schema_version(_version) do
    error("unsupported_schema", "schema_version must be #{@schema_version}")
  end

  defp validate_id(value, _name) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> error("invalid_manifest", "manifest identifiers must be UUIDs")
    end
  end

  defp validate_id(_value, _name) do
    error("invalid_manifest", "manifest identifiers must be UUID strings")
  end

  defp validate_sampling(nil) do
    Sampling.new()
  end

  defp validate_sampling(sampling) when is_map(sampling) do
    with :ok <- validate_fields(sampling, @sampling_fields, [], "sampling"),
         {:ok, reducer} <- sampling_reducer(sampling),
         :ok <- validate_minimum_pass_rate_field(sampling, reducer),
         {:ok, sampling} <-
           Sampling.new(
             samples: Map.get(sampling, "samples", 1),
             reducer: reducer
           ) do
      {:ok, sampling}
    else
      {:error, {:invalid_sampling, _message}} ->
        error("invalid_manifest", "sampling configuration is invalid")

      {:error, %{code: _code, message: _message} = error} ->
        {:error, error}
    end
  end

  defp validate_sampling(_sampling) do
    error("invalid_manifest", "sampling must be an object")
  end

  defp validate_sampling_struct(%__MODULE__{
         schema_version: @schema_version,
         sampling: %Sampling{} = sampling
       }) do
    case Sampling.new(sampling_options(sampling)) do
      {:ok, validated_sampling} ->
        {:ok, validated_sampling}

      {:error, {:invalid_sampling, _message}} ->
        error("invalid_manifest", "sampling configuration is invalid")
    end
  end

  defp validate_sampling_struct(%__MODULE__{}) do
    error("invalid_manifest", "file suite is not a validated schema-version-1 manifest")
  end

  defp sampling_reducer(sampling) do
    case Map.get(sampling, "reducer", "all") do
      reducer when reducer in @simple_reducers ->
        {:ok, String.to_existing_atom(reducer)}

      "minimum_pass_rate" ->
        {:ok, {:minimum_pass_rate, Map.get(sampling, "minimum_pass_rate")}}

      _reducer ->
        error("invalid_manifest", "sampling reducer is invalid")
    end
  end

  defp validate_minimum_pass_rate_field(sampling, {:minimum_pass_rate, _rate}) do
    if Map.has_key?(sampling, "minimum_pass_rate") do
      :ok
    else
      error("invalid_manifest", "minimum_pass_rate reducer requires a threshold")
    end
  end

  defp validate_minimum_pass_rate_field(sampling, _reducer) do
    if Map.has_key?(sampling, "minimum_pass_rate") do
      error("invalid_manifest", "minimum_pass_rate requires its matching reducer")
    else
      :ok
    end
  end

  defp fetch_suite(id) do
    fetch_target("suite", fn -> Evals.get_suite!(id) end)
  end

  defp fetch_prompt_version(id) do
    fetch_target("prompt_version", fn -> Prompts.get_prompt_version!(id) end)
  end

  defp fetch_provider(id) do
    fetch_target("provider", fn -> Providers.get_provider!(id) end)
  end

  defp fetch_target(resource, fetch) do
    {:ok, fetch.()}
  rescue
    _error in [Ecto.NoResultsError, Ecto.Query.CastError] ->
      error("#{resource}_not_found", "#{resource} was not found")
  end

  defp validate_prompt_version(%Suite{} = suite, %PromptVersion{} = prompt_version) do
    if prompt_version.prompt_id == suite.prompt_id do
      :ok
    else
      error("prompt_version_mismatch", "prompt_version does not belong to the suite prompt")
    end
  end

  defp execute_suite(
         %Suite{} = suite,
         %PromptVersion{} = prompt_version,
         %Provider{} = provider,
         %Sampling{} = sampling
       ) do
    case Evals.execute_suite(suite, prompt_version, provider, sampling_options(sampling)) do
      {:ok, suite_run} -> {:ok, suite_run}
      {:error, _reason} -> error("execution_failed", "suite execution could not be persisted")
    end
  rescue
    _error ->
      error("execution_failed", "suite execution failed")
  catch
    _kind, _reason ->
      error("execution_failed", "suite execution failed")
  end

  defp sampling_options(%Sampling{reducer: :minimum_pass_rate} = sampling) do
    [
      samples: sampling.samples,
      reducer: {:minimum_pass_rate, sampling.minimum_pass_rate}
    ]
  end

  defp sampling_options(%Sampling{} = sampling) do
    [samples: sampling.samples, reducer: sampling.reducer]
  end

  defp error(code, message) do
    {:error, %{code: code, message: message}}
  end
end
