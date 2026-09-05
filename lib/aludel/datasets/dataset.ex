defmodule Aludel.Datasets.Dataset do
  @moduledoc """
  A reusable collection of ordered evaluation examples.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Aludel.Datasets.DatasetEntry
  alias Ecto.Changeset

  @type t :: %__MODULE__{}

  @fields ~w(name description metadata)a

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "datasets" do
    field :name, :string
    field :description, :string
    field :metadata, :map, default: %{}

    has_many :entries, DatasetEntry

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for a dataset.

  Names are required and limited to 200 characters. Metadata must be JSON
  encodable so it can be persisted and queried consistently.
  """
  @spec changeset(t(), map()) :: Changeset.t()
  def changeset(dataset, attrs) do
    dataset
    |> cast(attrs, @fields)
    |> validate_required([:name, :metadata])
    |> validate_length(:name, max: 200)
    |> validate_json(:metadata)
  end

  defp validate_json(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      case Jason.encode(value) do
        {:ok, _encoded} -> []
        {:error, _reason} -> [{field, "must be JSON-encodable"}]
      end
    end)
  end
end
