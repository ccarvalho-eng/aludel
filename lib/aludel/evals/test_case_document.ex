defmodule Aludel.Evals.TestCaseDocument do
  @moduledoc """
  Schema for file attachments associated with test cases.

  Documents can be used to provide additional context or data for
  test cases, such as input files, reference documents, or
  expected outputs.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Aludel.Evals.TestCase
  alias Ecto.Changeset

  @type t :: %__MODULE__{}

  @max_size_bytes 10 * 1024 * 1024

  @supported_types ~w(
    image/png
    image/jpeg
    image/jpg
    application/pdf
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    text/csv
    application/json
    text/plain
  )

  @required_fields ~w(
    test_case_id
    filename
    content_type
    size_bytes
  )a
  @optional_fields ~w(data storage_key storage_backend)a
  @persisted_required_fields @required_fields ++ ~w(storage_key storage_backend)a
  @upload_required_fields @required_fields ++ ~w(data)a

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "test_case_documents" do
    field :filename, :string
    field :content_type, :string
    field :data, :binary, virtual: true
    field :storage_key, :string
    field :storage_backend, :string
    field :size_bytes, :integer

    belongs_to(:test_case, TestCase)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns maximum allowed file size in bytes.
  """
  @spec max_size_bytes() :: non_neg_integer()
  def max_size_bytes, do: @max_size_bytes

  @doc """
  Returns list of supported MIME types.
  """
  @spec supported_types() :: [String.t()]
  def supported_types, do: @supported_types

  @doc """
  Changeset for persisted test case document rows.
  """
  @spec changeset(t(), map()) :: Changeset.t()
  def changeset(test_case_document, attrs) do
    test_case_document
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@persisted_required_fields)
    |> validate_common_fields()
    |> validate_persisted_storage_location()
    |> unique_constraint(:storage_key, name: :test_case_documents_storage_reference_index)
    |> check_constraint(:storage_key, name: :test_case_documents_external_storage_required)
    |> foreign_key_constraint(:test_case_id)
  end

  @doc """
  Changeset for new uploads before the document is persisted externally.
  """
  @spec create_changeset(t(), map()) :: Changeset.t()
  def create_changeset(test_case_document, attrs) do
    test_case_document
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@upload_required_fields)
    |> validate_common_fields()
    |> validate_upload_storage_location()
    |> foreign_key_constraint(:test_case_id)
  end

  @doc """
  Returns whether the document references content in a configured storage backend.
  """
  @spec externally_stored?(t()) :: boolean()
  def externally_stored?(%__MODULE__{storage_key: storage_key}), do: is_binary(storage_key)

  defp validate_common_fields(changeset) do
    changeset
    |> validate_inclusion(:content_type, @supported_types,
      message: "is not a supported document type"
    )
    |> validate_number(:size_bytes,
      less_than_or_equal_to: @max_size_bytes,
      message: "file size must be less than 10MB"
    )
    |> validate_length(:filename, max: 255)
    |> validate_length(:content_type, max: 100)
    |> validate_length(:storage_key, max: 1024)
    |> validate_length(:storage_backend, max: 255)
  end

  defp validate_persisted_storage_location(changeset) do
    case get_field(changeset, :data) do
      nil -> changeset
      _data -> add_error(changeset, :data, "must be blank for persisted documents")
    end
  end

  defp validate_upload_storage_location(changeset) do
    storage_key = get_field(changeset, :storage_key)
    storage_backend = get_field(changeset, :storage_backend)

    changeset
    |> maybe_add_upload_storage_error(:storage_key, storage_key)
    |> maybe_add_upload_storage_error(:storage_backend, storage_backend)
  end

  defp maybe_add_upload_storage_error(changeset, _field, value) when not is_binary(value),
    do: changeset

  defp maybe_add_upload_storage_error(changeset, field, _value) do
    add_error(changeset, field, "must be blank for uploaded documents")
  end
end
