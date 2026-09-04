defmodule Aludel.Datasets.DatasetEntry do
  @moduledoc """
  An ordered single-turn or multi-turn example in a dataset.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Aludel.Datasets.Dataset
  alias Aludel.Evals.{AssertionParser, MessageValidator}
  alias Ecto.Changeset

  @type t :: %__MODULE__{}

  @fields ~w(name variable_values messages assertions metadata position)a

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dataset_entries" do
    field :name, :string
    field :variable_values, :map, default: %{}
    field :messages, {:array, :map}, default: []
    field :assertions, {:array, :map}, default: []
    field :metadata, :map, default: %{}
    field :position, :integer
    field :red_team_deduplication_key, :string

    belongs_to :dataset, Dataset

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Changeset.t()
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, @fields)
    |> validate_required([
      :dataset_id,
      :name,
      :variable_values,
      :messages,
      :assertions,
      :metadata,
      :position
    ])
    |> validate_length(:name, max: 200)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_messages()
    |> validate_assertions()
    |> validate_json(:variable_values)
    |> validate_json(:metadata)
    |> validate_payload()
    |> foreign_key_constraint(:dataset_id)
    |> unique_constraint(:position, name: :dataset_entries_dataset_id_position_index)
    |> unique_constraint(:red_team_deduplication_key,
      name: :dataset_entries_red_team_deduplication_index
    )
  end

  @spec conversation_kind(t()) :: :single_turn | :multi_turn
  def conversation_kind(%__MODULE__{messages: messages}) when length(messages) > 1 do
    :multi_turn
  end

  def conversation_kind(%__MODULE__{}) do
    :single_turn
  end

  defp validate_messages(changeset) do
    validate_change(changeset, :messages, fn :messages, messages ->
      case MessageValidator.validate(messages) do
        :ok -> []
        {:error, message} -> [messages: message]
      end
    end)
  end

  defp validate_assertions(changeset) do
    validate_change(changeset, :assertions, fn :assertions, assertions ->
      case AssertionParser.validate(assertions) do
        {:ok, _assertions} -> []
        {:error, message} -> [assertions: message]
      end
    end)
  end

  defp validate_json(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      case Jason.encode(value) do
        {:ok, _encoded} -> []
        {:error, _reason} -> [{field, "must be JSON-encodable"}]
      end
    end)
  end

  defp validate_payload(changeset) do
    variable_values = get_field(changeset, :variable_values) || %{}
    messages = get_field(changeset, :messages) || []

    if variable_values == %{} and messages == [] do
      add_error(changeset, :variable_values, "must include variables or messages")
    else
      changeset
    end
  end
end
