defmodule Aludel.Datasets do
  @moduledoc """
  Context for reusable evaluation datasets and suite population.
  """

  import Ecto.Query

  alias Aludel.Datasets.{Dataset, DatasetEntry}
  alias Aludel.Evals.{Suite, TestCase}
  alias Ecto.Changeset

  @doc """
  Lists datasets alphabetically by name.
  """
  @spec list_datasets() :: [Dataset.t()]
  def list_datasets do
    Dataset
    |> order_by([dataset], asc: dataset.name)
    |> repo().all()
  end

  @doc """
  Fetches a dataset by ID and raises `Ecto.NoResultsError` when it does not exist.
  """
  @spec get_dataset!(binary()) :: Dataset.t()
  def get_dataset!(id) do
    repo().get!(Dataset, id)
  end

  @doc """
  Fetches a dataset by ID.

  Returns `nil` for an invalid UUID or a dataset that does not exist.
  """
  @spec get_dataset(binary()) :: Dataset.t() | nil
  def get_dataset(id) do
    case Ecto.UUID.cast(id) do
      {:ok, dataset_id} -> repo().get(Dataset, dataset_id)
      :error -> nil
    end
  end

  @doc """
  Lists a dataset's entries in stable position and insertion order.

  Pass `metadata: %{...}` to retain entries whose JSON metadata contains every
  supplied key and value.
  """
  @spec list_entries(Dataset.t(), keyword()) :: [DatasetEntry.t()]
  def list_entries(%Dataset{} = dataset, opts \\ []) do
    DatasetEntry
    |> where([entry], entry.dataset_id == ^dataset.id)
    |> filter_entries_by_metadata(Keyword.get(opts, :metadata, %{}))
    |> order_by([entry], asc: entry.position, asc: entry.inserted_at)
    |> repo().all()
  end

  @doc """
  Fetches a dataset with its entries preloaded in stable order.

  Raises `Ecto.NoResultsError` when the dataset does not exist.
  """
  @spec get_dataset_with_entries!(binary()) :: Dataset.t()
  def get_dataset_with_entries!(id) do
    entries = from entry in DatasetEntry, order_by: [asc: entry.position, asc: entry.inserted_at]

    Dataset
    |> repo().get!(id)
    |> repo().preload(entries: entries)
  end

  @doc """
  Fetches an entry by ID within a dataset.

  Returns `nil` for an invalid UUID, a missing entry, or an entry owned by a
  different dataset.
  """
  @spec get_entry(Dataset.t(), binary()) :: DatasetEntry.t() | nil
  def get_entry(%Dataset{} = dataset, id) do
    case Ecto.UUID.cast(id) do
      {:ok, entry_id} ->
        DatasetEntry
        |> where([entry], entry.dataset_id == ^dataset.id and entry.id == ^entry_id)
        |> repo().one()

      :error ->
        nil
    end
  end

  @doc """
  Creates a reusable dataset from the supplied attributes.
  """
  @spec create_dataset(map()) :: {:ok, Dataset.t()} | {:error, Changeset.t()}
  def create_dataset(attrs) do
    %Dataset{}
    |> Dataset.changeset(attrs)
    |> repo().insert()
  end

  @doc """
  Updates a dataset's name, description, or metadata.
  """
  @spec update_dataset(Dataset.t(), map()) :: {:ok, Dataset.t()} | {:error, Changeset.t()}
  def update_dataset(%Dataset{} = dataset, attrs) do
    dataset
    |> Dataset.changeset(attrs)
    |> repo().update()
  end

  @doc """
  Deletes a dataset.

  Associated entries are removed according to the repository constraint.
  """
  @spec delete_dataset(Dataset.t()) :: {:ok, Dataset.t()} | {:error, Changeset.t()}
  def delete_dataset(%Dataset{} = dataset) do
    repo().delete(dataset)
  end

  @doc """
  Returns a dataset changeset without persisting it.
  """
  @spec change_dataset(Dataset.t(), map()) :: Changeset.t()
  def change_dataset(%Dataset{} = dataset, attrs \\ %{}) do
    Dataset.changeset(dataset, attrs)
  end

  @doc """
  Creates an ordered entry in a dataset.

  When no position is supplied, the entry is appended atomically. Concurrent
  inserts serialize on the dataset row so they cannot claim the same position.
  """
  @spec create_entry(Dataset.t(), map()) ::
          {:ok, DatasetEntry.t()} | {:error, Changeset.t()}
  def create_entry(%Dataset{} = dataset, attrs) do
    repo().transaction(fn ->
      lock_dataset!(dataset.id)
      position = entry_position(attrs, next_position(dataset.id))

      %DatasetEntry{dataset_id: dataset.id}
      |> DatasetEntry.changeset(Map.put(attrs, :position, position))
      |> repo().insert()
      |> case do
        {:ok, entry} -> entry
        {:error, changeset} -> repo().rollback(changeset)
      end
    end)
  end

  @doc """
  Updates an entry while preserving its dataset ownership.

  Any `dataset_id` attribute is discarded.
  """
  @spec update_entry(DatasetEntry.t(), map()) ::
          {:ok, DatasetEntry.t()} | {:error, Changeset.t()}
  def update_entry(%DatasetEntry{} = entry, attrs) do
    entry
    |> DatasetEntry.changeset(Map.drop(attrs, [:dataset_id, "dataset_id"]))
    |> repo().update()
  end

  @doc """
  Deletes a dataset entry.
  """
  @spec delete_entry(DatasetEntry.t()) ::
          {:ok, DatasetEntry.t()} | {:error, Changeset.t()}
  def delete_entry(%DatasetEntry{} = entry) do
    repo().delete(entry)
  end

  @doc """
  Returns an entry changeset without persisting it.
  """
  @spec change_entry(DatasetEntry.t(), map()) :: Changeset.t()
  def change_entry(%DatasetEntry{} = entry, attrs \\ %{}) do
    DatasetEntry.changeset(entry, attrs)
  end

  @doc """
  Copies entries from a dataset into an evaluation suite.

  Entries already linked to the suite through `source_dataset_entry_id` are
  skipped. The operation is transactional and safe to repeat.
  """
  @spec populate_suite(Dataset.t(), Suite.t()) ::
          {:ok, [TestCase.t()]} | {:error, term()}
  def populate_suite(%Dataset{} = dataset, %Suite{} = suite) do
    repo().transaction(fn ->
      lock_suite!(suite.id)

      dataset.id
      |> dataset_entries_not_in_suite(suite.id)
      |> Enum.map(&insert_dataset_entry_copy(&1, suite.id))
    end)
  end

  defp dataset_entries_not_in_suite(dataset_id, suite_id) do
    imported_entry_ids =
      from(test_case in TestCase,
        where:
          test_case.suite_id == ^suite_id and
            not is_nil(test_case.source_dataset_entry_id),
        select: test_case.source_dataset_entry_id
      )

    from(entry in DatasetEntry,
      where: entry.dataset_id == ^dataset_id and entry.id not in subquery(imported_entry_ids),
      order_by: [asc: entry.position, asc: entry.inserted_at]
    )
    |> repo().all()
  end

  defp filter_entries_by_metadata(query, metadata) when map_size(metadata) == 0 do
    query
  end

  defp filter_entries_by_metadata(query, metadata) do
    where(query, [entry], fragment("? @> ?", entry.metadata, ^metadata))
  end

  defp lock_dataset!(dataset_id) do
    Dataset
    |> where([dataset], dataset.id == ^dataset_id)
    |> lock("FOR UPDATE")
    |> repo().one!()
  end

  defp lock_suite!(suite_id) do
    Suite
    |> where([suite], suite.id == ^suite_id)
    |> lock("FOR UPDATE")
    |> repo().one!()
  end

  defp insert_dataset_entry_copy(entry, suite_id) do
    attrs = %{
      variable_values: entry.variable_values,
      messages: entry.messages,
      assertions: entry.assertions,
      metadata: entry.metadata
    }

    %TestCase{suite_id: suite_id, source_dataset_entry_id: entry.id}
    |> TestCase.changeset(attrs)
    |> repo().insert()
    |> case do
      {:ok, test_case} -> test_case
      {:error, changeset} -> repo().rollback(changeset)
    end
  end

  defp next_position(dataset_id) do
    from(entry in DatasetEntry,
      where: entry.dataset_id == ^dataset_id,
      select: max(entry.position)
    )
    |> repo().one()
    |> case do
      nil -> 0
      position -> position + 1
    end
  end

  defp entry_position(%{position: position}, _default) when position not in [nil, false] do
    position
  end

  defp entry_position(%{"position" => position}, _default) when position not in [nil, false] do
    position
  end

  defp entry_position(_attrs, default) do
    default
  end

  defp repo do
    Aludel.Repo.get()
  end
end
