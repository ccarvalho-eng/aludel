defmodule Aludel.RedTeam.DatasetImporter do
  @moduledoc false

  import Ecto.Query

  alias Aludel.Datasets.{Dataset, DatasetEntry}
  alias Ecto.Changeset

  @max_deduplication_key_bytes 255
  @hashed_key_prefix "aludel:red_team:sha256:"

  @type prepared_entry :: %{
          deduplication_key: String.t(),
          attrs: map()
        }
  @type result :: %{created: [DatasetEntry.t()], skipped: [DatasetEntry.t()]}
  @type error ::
          :dataset_not_found
          | {:deduplication_conflict, String.t()}
          | Changeset.t()

  @spec persist(Ecto.UUID.t(), [prepared_entry()]) :: {:ok, result()} | {:error, error()}
  def persist(dataset_id, prepared_entries) do
    repo().transaction(fn ->
      case lock_dataset(dataset_id) do
        nil -> repo().rollback(:dataset_not_found)
        dataset -> persist_locked(dataset, prepared_entries)
      end
    end)
  end

  @spec bounded_key(String.t()) :: String.t()
  def bounded_key(key) when byte_size(key) <= @max_deduplication_key_bytes do
    key
  end

  def bounded_key(key) do
    @hashed_key_prefix <> sha256(key)
  end

  defp persist_locked(dataset, prepared_entries) do
    keys = Enum.map(prepared_entries, & &1.deduplication_key)
    entries = list_entries_with_keys(dataset.id, keys)
    next_position = next_position(dataset.id)

    prepared_entries
    |> Enum.reduce_while({[], [], next_position}, fn prepared, {created, skipped, position} ->
      case persist_entry(dataset.id, prepared, entries, position) do
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

  defp persist_entry(dataset_id, prepared, entries, position) do
    attrs = Map.put(prepared.attrs, :position, position)

    case entries_with_key(entries, prepared.deduplication_key) do
      [] ->
        insert_entry(dataset_id, prepared.deduplication_key, attrs)

      [entry] ->
        if matches_import?(entry, prepared.deduplication_key, attrs) do
          {:skipped, entry}
        else
          {:error, {:deduplication_conflict, prepared.deduplication_key}}
        end

      _duplicates ->
        {:error, {:deduplication_conflict, prepared.deduplication_key}}
    end
  end

  defp insert_entry(dataset_id, deduplication_key, attrs) do
    changeset =
      %DatasetEntry{
        dataset_id: dataset_id,
        red_team_deduplication_key: deduplication_key
      }
      |> DatasetEntry.changeset(attrs)

    case repo().insert(changeset) do
      {:ok, entry} -> {:created, entry}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp matches_import?(entry, deduplication_key, attrs) do
    entry.name == attrs.name and
      entry.variable_values == attrs.variable_values and
      entry.messages == [] and
      entry.assertions == attrs.assertions and
      entry.red_team_deduplication_key == deduplication_key and
      entry.metadata["red_team"] == attrs.metadata["red_team"]
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
    |> lock("FOR UPDATE")
    |> repo().all()
  end

  defp entries_with_key(entries, key) do
    Enum.filter(entries, &(&1.red_team_deduplication_key == key))
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

  defp sha256(value) do
    value
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp repo do
    Aludel.Repo.get()
  end
end
