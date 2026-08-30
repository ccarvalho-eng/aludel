defmodule Aludel.Evals.TestCase do
  @moduledoc """
  Schema for individual test cases within a suite.

  Test cases define variable values to substitute into prompts
  and assertions to validate the LLM output.

  Supported assertion types:
  - contains: Check if output contains a specific string
  - not_contains: Check if output does not contain a string
  - regex: Match output against a regular expression
  - exact_match: Check for exact string match
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Aludel.Datasets.DatasetEntry
  alias Aludel.Evals.{AssertionParser, MessageValidator, Suite, TestCaseDocument}
  alias Ecto.Changeset

  @type t :: %__MODULE__{}

  @required_fields ~w(suite_id variable_values assertions)a
  @optional_fields ~w(messages metadata)a

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "test_cases" do
    field :variable_values, :map
    field :assertions, {:array, :map}
    field :messages, {:array, :map}, default: []
    field :metadata, :map, default: %{}

    belongs_to(:suite, Suite)
    belongs_to(:source_dataset_entry, DatasetEntry)
    has_many(:documents, TestCaseDocument, on_delete: :delete_all)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a test case.

  Validates that suite_id, variable_values, and assertions are
  present.
  """
  @spec changeset(t(), map()) :: Changeset.t()
  def changeset(test_case, attrs) do
    test_case
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields ++ [:messages, :metadata])
    |> validate_messages()
    |> validate_assertions()
    |> validate_json(:variable_values)
    |> validate_json(:metadata)
    |> foreign_key_constraint(:suite_id)
    |> foreign_key_constraint(:source_dataset_entry_id)
    |> unique_constraint(:source_dataset_entry_id,
      name: :test_cases_suite_id_source_dataset_entry_id_index
    )
  end

  defp validate_assertions(%Changeset{} = changeset) do
    validate_change(changeset, :assertions, fn :assertions, assertions ->
      case AssertionParser.validate(assertions) do
        {:ok, _assertions} -> []
        {:error, message} -> [assertions: message]
      end
    end)
  end

  defp validate_messages(%Changeset{} = changeset) do
    validate_change(changeset, :messages, fn :messages, messages ->
      case MessageValidator.validate(messages) do
        :ok -> []
        {:error, message} -> [messages: message]
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
end
