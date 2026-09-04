defmodule Aludel.RedTeam do
  @moduledoc """
  Curated and generated adversarial evaluation cases.

  Catalog cases can be inspected directly or materialized into an existing
  reusable dataset. Materialization is transactional and idempotent for the
  same case version and prompt variable. It records provenance, risk category,
  severity, content checksum, and a stable deduplication key in entry metadata.

  Curated cases include deterministic canary assertions. Generated cases are
  returned as inert review values without database writes or execution.
  """

  import Ecto.Query

  alias Aludel.Datasets.{Dataset, DatasetEntry}
  alias Aludel.RedTeam.Catalog
  alias Aludel.RedTeam.Generation
  alias Aludel.RedTeam.Generator
  alias Ecto.Changeset

  @default_variable "input"
  @default_judge_threshold 80
  @type category :: Catalog.category()
  @type template :: Catalog.template()
  @type materialization :: %{
          created: [DatasetEntry.t()],
          skipped: [DatasetEntry.t()]
        }
  @type materialize_error ::
          :dataset_not_found
          | :invalid_options
          | :invalid_variable
          | :invalid_judge_provider_id
          | :invalid_judge_threshold
          | {:unknown_categories, [term()]}
          | {:unknown_case_ids, [term()]}
          | {:deduplication_conflict, String.t()}
          | Changeset.t()
  @type generate_error ::
          :provider_not_found
          | :invalid_options
          | :invalid_categories
          | :invalid_cases_per_category
          | :invalid_target_context
          | :invalid_budget
          | {:unknown_categories, [term()]}

  @doc """
  Returns every case in stable catalog order.
  """
  @spec all() :: [template()]
  def all do
    Catalog.all()
  end

  @doc """
  Returns the supported risk categories in alphabetical order.
  """
  @spec categories() :: [category()]
  def categories do
    Catalog.categories()
  end

  @doc """
  Fetches a catalog case by its stable ID.
  """
  @spec fetch(String.t()) :: {:ok, template()} | :error
  def fetch(id) do
    Catalog.fetch(id)
  end

  @doc """
  Fetches a catalog case by its stable ID, raising `KeyError` when absent.
  """
  @spec fetch!(String.t()) :: template()
  def fetch!(id) do
    Catalog.fetch!(id)
  end

  @doc """
  Generates bounded, reviewable adversarial cases without persisting them.

  Generation runs once per selected category and records sanitized failures,
  observed token and cost usage, and the configured limits. Successfully
  validated categories remain available when another category fails.

  Options:

    * `:categories` - non-empty, unique category list; defaults to `[:prompt_injection]`
    * `:cases_per_category` - cases requested per category from 1 to 5; defaults to 2
    * `:target_context` - optional product or policy context, limited to 10,000 characters
    * `:max_requests` - category request limit from 1 to 6; defaults to 6
    * `:max_output_tokens` - per-request output limit from 100 to 4,000; defaults to 1,200
    * `:max_total_tokens` - observed token stop threshold up to 100,000; defaults to 20,000
    * `:max_cost_usd` - observed cost stop threshold greater than 0 and up to 100; defaults to 5
    * `:request_timeout_ms` - per-request timeout from 100 to 120,000; defaults to 30,000

  See `Aludel.RedTeam.Generation` for the returned review boundary. Review the
  candidates and failures before deciding whether any case should enter an
  evaluation dataset.
  """
  @spec generate(String.t(), keyword()) ::
          {:ok, Generation.t()} | {:error, generate_error()}
  def generate(provider_id, opts \\ []) do
    Generator.generate(provider_id, opts)
  end

  @doc """
  Materializes selected catalog cases into an existing dataset.

  Options:

    * `:categories` - category atoms to include; defaults to every category
    * `:case_ids` - stable case IDs to include; defaults to every case
    * `:variable` - prompt variable populated by each case; defaults to `"input"`
    * `:judge_provider_id` - optional provider UUID for a recommended rubric judge
    * `:judge_threshold` - rubric judge pass threshold from 0 to 100; defaults to 80

  The two selectors are combined. Repeating a materialization with the same
  case version and variable skips the previously created entries. A checksum
  mismatch under the same deduplication key returns an error instead of silently
  accepting different content.
  """
  @spec materialize(Dataset.t(), keyword()) ::
          {:ok, materialization()} | {:error, materialize_error()}
  def materialize(dataset, opts \\ [])

  def materialize(%Dataset{} = dataset, opts) when is_list(opts) do
    with {:ok, dataset_id} <- validate_dataset_id(dataset.id),
         {:ok, normalized} <- validate_options(opts),
         {:ok, selected} <- select_cases(normalized) do
      persist_cases(dataset_id, selected, normalized)
    end
  end

  def materialize(%Dataset{}, _opts) do
    {:error, :invalid_options}
  end

  defp validate_options(opts) do
    defaults = [
      categories: Catalog.categories(),
      case_ids: Enum.map(Catalog.all(), & &1.id),
      variable: @default_variable,
      judge_provider_id: nil,
      judge_threshold: @default_judge_threshold
    ]

    case Keyword.validate(opts, defaults) do
      {:ok, normalized} -> validate_normalized_options(normalized)
      {:error, _unknown} -> {:error, :invalid_options}
    end
  end

  defp validate_normalized_options(opts) do
    with :ok <- validate_variable(opts[:variable]),
         :ok <- validate_judge_provider_id(opts[:judge_provider_id]),
         :ok <- validate_judge_threshold(opts[:judge_threshold]) do
      {:ok, opts}
    end
  end

  defp validate_dataset_id(dataset_id) do
    case Ecto.UUID.cast(dataset_id) do
      {:ok, normalized_id} -> {:ok, normalized_id}
      :error -> {:error, :dataset_not_found}
    end
  end

  defp validate_variable(variable) when is_binary(variable) do
    if String.valid?(variable) and
         byte_size(variable) <= 200 and
         Regex.match?(~r/\A[a-zA-Z_][a-zA-Z0-9_.-]*\z/u, variable) do
      :ok
    else
      {:error, :invalid_variable}
    end
  end

  defp validate_variable(_variable) do
    {:error, :invalid_variable}
  end

  defp validate_judge_provider_id(nil) do
    :ok
  end

  defp validate_judge_provider_id(provider_id) when is_binary(provider_id) do
    case Ecto.UUID.cast(provider_id) do
      {:ok, _provider_id} -> :ok
      :error -> {:error, :invalid_judge_provider_id}
    end
  end

  defp validate_judge_provider_id(_provider_id) do
    {:error, :invalid_judge_provider_id}
  end

  defp validate_judge_threshold(threshold)
       when is_number(threshold) and threshold >= 0 and threshold <= 100 do
    :ok
  end

  defp validate_judge_threshold(_threshold) do
    {:error, :invalid_judge_threshold}
  end

  defp select_cases(opts) do
    categories = opts[:categories]
    case_ids = opts[:case_ids]

    with :ok <- validate_categories(categories),
         :ok <- validate_case_ids(case_ids) do
      selected =
        all()
        |> Enum.filter(&(&1.category in categories and &1.id in case_ids))

      {:ok, selected}
    end
  end

  defp validate_categories(categories) when is_list(categories) do
    case Enum.reject(categories, &(&1 in Catalog.categories())) do
      [] -> :ok
      unknown -> {:error, {:unknown_categories, unknown}}
    end
  end

  defp validate_categories(categories) do
    {:error, {:unknown_categories, List.wrap(categories)}}
  end

  defp validate_case_ids(case_ids) when is_list(case_ids) do
    known_ids = Enum.map(Catalog.all(), & &1.id)

    case Enum.reject(case_ids, &(&1 in known_ids)) do
      [] -> :ok
      unknown -> {:error, {:unknown_case_ids, unknown}}
    end
  end

  defp validate_case_ids(case_ids) do
    {:error, {:unknown_case_ids, List.wrap(case_ids)}}
  end

  defp persist_cases(dataset_id, selected, opts) do
    repo().transaction(fn ->
      case lock_dataset(dataset_id) do
        nil -> repo().rollback(:dataset_not_found)
        locked_dataset -> materialize_locked(locked_dataset, selected, opts)
      end
    end)
  end

  defp materialize_locked(dataset, selected, opts) do
    keys = Enum.map(selected, &deduplication_key(&1, opts[:variable]))
    entries = list_entries_with_keys(dataset.id, keys)
    next_position = next_position(dataset.id)

    selected
    |> Enum.reduce_while({[], [], next_position}, fn template, {created, skipped, position} ->
      case materialize_template(dataset.id, template, opts, entries, position) do
        {:created, entry} ->
          {:cont, {[entry | created], skipped, position + 1}}

        {:skipped, entry} ->
          {:cont, {created, [entry | skipped], position}}

        {:error, reason} ->
          repo().rollback(reason)
      end
    end)
    |> then(fn {created, skipped, _position} ->
      %{created: Enum.reverse(created), skipped: Enum.reverse(skipped)}
    end)
  end

  defp entry_attrs(template, opts, position) do
    variable = opts[:variable]
    assertions = assertions(template, opts)

    %{
      name: template.name,
      variable_values: %{variable => template.prompt},
      assertions: assertions,
      metadata: metadata(template, variable, opts),
      position: position
    }
  end

  defp materialize_template(dataset_id, template, opts, entries, position) do
    attrs = entry_attrs(template, opts, position)
    key = get_in(attrs, [:metadata, "red_team", "deduplication_key"])

    case entries_with_key(entries, key) do
      [] ->
        case insert_entry(dataset_id, attrs) do
          {:ok, entry} -> {:created, entry}
          {:error, changeset} -> {:error, changeset}
        end

      [entry] ->
        if matches_materialization?(entry, attrs) do
          {:skipped, entry}
        else
          {:error, {:deduplication_conflict, key}}
        end

      _duplicates ->
        {:error, {:deduplication_conflict, key}}
    end
  end

  defp assertions(template, opts) do
    case opts[:judge_provider_id] do
      nil ->
        template.assertions

      provider_id ->
        template.assertions ++
          [
            %{
              "type" => "rubric_judge",
              "template" => template.judge_template,
              "provider_id" => provider_id,
              "threshold" => opts[:judge_threshold]
            }
          ]
    end
  end

  defp metadata(template, variable, opts) do
    %{
      "red_team" => %{
        "catalog" => Catalog.name(),
        "catalog_version" => Catalog.version(),
        "case_id" => template.id,
        "case_version" => template.version,
        "category" => Atom.to_string(template.category),
        "severity" => Atom.to_string(template.severity),
        "technique" => Atom.to_string(template.technique),
        "risk_reference" => template.risk_reference,
        "recommended_judge" => template.judge_template,
        "template_checksum" => template.checksum,
        "checksum" => materialization_checksum(template, variable, opts),
        "deduplication_key" => deduplication_key(template, variable),
        "provenance" => %{
          "source" => "Aludel curated red-team catalog",
          "catalog" => Catalog.name(),
          "version" => Catalog.version()
        }
      }
    }
  end

  defp materialization_checksum(template, variable, opts) do
    judge_provider_id = opts[:judge_provider_id] || ""

    judge_threshold =
      if opts[:judge_provider_id] do
        to_string(opts[:judge_threshold])
      else
        ""
      end

    [template.checksum, variable, judge_provider_id, judge_threshold]
    |> Enum.join("\u0000")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp deduplication_key(template, variable) do
    "aludel:red_team:#{Catalog.name()}@#{Catalog.version()}:#{template.id}@#{template.version}:#{variable}"
  end

  defp lock_dataset(dataset_id) do
    Dataset
    |> where([dataset], dataset.id == ^dataset_id)
    |> lock("FOR UPDATE")
    |> repo().one()
  end

  defp list_entries_with_keys(_dataset_id, []) do
    []
  end

  defp list_entries_with_keys(dataset_id, keys) do
    DatasetEntry
    |> where(
      [entry],
      entry.dataset_id == ^dataset_id and entry.red_team_deduplication_key in ^keys
    )
    |> repo().all()
  end

  defp entries_with_key(entries, key) do
    Enum.filter(entries, fn entry ->
      entry.red_team_deduplication_key == key
    end)
  end

  defp matches_materialization?(entry, attrs) do
    entry.name == attrs.name and
      entry.variable_values == attrs.variable_values and
      entry.messages == [] and
      entry.assertions == attrs.assertions and
      entry.red_team_deduplication_key ==
        get_in(attrs, [:metadata, "red_team", "deduplication_key"]) and
      entry.metadata["red_team"] == attrs.metadata["red_team"]
  end

  defp next_position(dataset_id) do
    DatasetEntry
    |> where([entry], entry.dataset_id == ^dataset_id)
    |> select([entry], max(entry.position))
    |> repo().one()
    |> case do
      nil -> 0
      position -> position + 1
    end
  end

  defp insert_entry(dataset_id, attrs) do
    deduplication_key = get_in(attrs, [:metadata, "red_team", "deduplication_key"])

    %DatasetEntry{
      dataset_id: dataset_id,
      red_team_deduplication_key: deduplication_key
    }
    |> DatasetEntry.changeset(attrs)
    |> repo().insert()
  end

  defp repo do
    Aludel.Repo.get()
  end
end
