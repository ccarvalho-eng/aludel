defmodule Aludel.Evals.DocumentIngestion do
  @moduledoc """
  Validates and persists uploaded documents for suite test cases.
  """

  import Ecto.Changeset, only: [traverse_errors: 2]

  alias Aludel.Evals
  alias Aludel.FileValidation

  @type ingest_result ::
          {:success, String.t()}
          | {:failed, String.t(), String.t()}

  @doc """
  Validates an uploaded file and attaches it to a test case.

  The return value identifies the client filename on both success and failure,
  making it suitable for aggregating LiveView upload results.
  """
  @spec ingest(String.t(), Phoenix.LiveView.UploadEntry.t(), binary()) :: ingest_result()
  def ingest(path, entry, test_case_id) do
    case File.read(path) do
      {:ok, data} ->
        validate_and_persist(data, entry, test_case_id)

      {:error, reason} ->
        {:failed, entry.client_name, reason |> :file.format_error() |> to_string()}
    end
  end

  defp validate_and_persist(data, entry, test_case_id) do
    case FileValidation.validate(data, entry.client_type) do
      :ok ->
        persist_document(entry, data, test_case_id)

      {:error, reason} ->
        {:failed, entry.client_name, reason}
    end
  end

  defp persist_document(entry, data, test_case_id) do
    case Evals.create_test_case_document(%{
           test_case_id: test_case_id,
           filename: entry.client_name,
           content_type: entry.client_type,
           data: data,
           size_bytes: entry.client_size
         }) do
      {:ok, _document} ->
        {:success, entry.client_name}

      {:error, changeset} ->
        {:failed, entry.client_name, format_changeset_errors(changeset)}
    end
  end

  defp format_changeset_errors(changeset) do
    changeset
    |> traverse_errors(fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join(", ", fn {field, messages} ->
      "#{field} #{Enum.join(messages, ", ")}"
    end)
  end
end
