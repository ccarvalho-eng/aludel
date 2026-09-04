defmodule Aludel.Runs.RunResult do
  @moduledoc """
  Schema for run results.

  A run result captures lifecycle state, output, metrics, callback metadata, and
  normalized execution artifacts for one provider in a multi-provider run.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Aludel.Providers.Provider
  alias Aludel.Runs.Run
  alias Ecto.Changeset

  @type t :: %__MODULE__{}

  @required_fields ~w(run_id provider_id status)a
  @optional_fields ~w(output input_tokens output_tokens latency_ms cost_usd metadata artifacts error started_at completed_at)a

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "run_results" do
    field :output, :string
    field :input_tokens, :integer
    field :output_tokens, :integer
    field :latency_ms, :integer
    field :cost_usd, :float
    field :metadata, :map
    field :artifacts, :map
    field :status, Ecto.Enum, values: [:pending, :running, :completed, :error]
    field :error, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to(:run, Run)
    belongs_to(:provider, Provider)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a run result.

  Validates that run_id, provider_id, and status are present.
  """
  @spec changeset(t(), map()) :: Changeset.t()
  def changeset(run_result, attrs) do
    run_result
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_change(:metadata, &validate_json_encodable_metadata/2)
    |> validate_change(:artifacts, &validate_json_encodable_artifacts/2)
    |> foreign_key_constraint(:run_id)
    |> foreign_key_constraint(:provider_id)
  end

  defp validate_json_encodable_metadata(:metadata, metadata) do
    case Jason.encode(metadata) do
      {:ok, _encoded_metadata} -> []
      {:error, _reason} -> [metadata: "must be JSON-encodable"]
    end
  end

  defp validate_json_encodable_artifacts(:artifacts, artifacts) do
    case Jason.encode(artifacts) do
      {:ok, _encoded_artifacts} -> []
      {:error, _reason} -> [artifacts: "must be JSON-encodable"]
    end
  end
end
