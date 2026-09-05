defmodule Aludel.Evals.SuiteRun do
  @moduledoc """
  Schema for tracking suite execution results.

  Records the outcome of running a test suite against a specific
  prompt version and provider, storing individual test results and
  summary counts. Runs with a quality policy retain the immutable policy
  association and its evaluated rule evidence.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Aludel.Evals.{Suite, SuitePolicy}
  alias Aludel.Prompts.PromptVersion
  alias Aludel.Providers.Provider
  alias Ecto.Changeset

  @type t :: %__MODULE__{}

  @required_fields ~w(suite_id prompt_version_id provider_id)a
  @optional_fields ~w(
    results
    passed
    failed
    avg_cost_usd
    avg_latency_ms
    avg_score
    total_cost_usd
    cost_sample_count
    total_latency_ms
    latency_sample_count
    suite_policy_id
    quality_policy_result
  )a

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "suite_runs" do
    field :results, {:array, :map}, default: []
    field :passed, :integer, default: 0
    field :failed, :integer, default: 0
    field :avg_cost_usd, :decimal
    field :avg_latency_ms, :integer
    field :avg_score, :decimal
    field :total_cost_usd, :decimal
    field :cost_sample_count, :integer, default: 0
    field :total_latency_ms, :integer
    field :latency_sample_count, :integer, default: 0
    field :quality_policy_result, :map
    field :lock_version, :integer, default: 1

    belongs_to(:suite, Suite)
    belongs_to(:suite_policy, SuitePolicy)
    belongs_to(:prompt_version, PromptVersion)
    belongs_to(:provider, Provider)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a suite run.

  Validates that suite_id, prompt_version_id, and provider_id are
  present.
  """
  @spec changeset(t(), map()) :: Changeset.t()
  def changeset(suite_run, attrs) do
    suite_run
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_quality_policy_pair()
    |> foreign_key_constraint(:suite_policy_id)
  end

  defp validate_quality_policy_pair(changeset) do
    case {get_field(changeset, :suite_policy_id), get_field(changeset, :quality_policy_result)} do
      {nil, nil} ->
        changeset

      {nil, _result} ->
        add_error(
          changeset,
          :quality_policy_result,
          "must be stored with its policy association"
        )

      {_policy_id, nil} ->
        add_error(changeset, :suite_policy_id, "must be stored with its policy result")

      {_policy_id, _result} ->
        changeset
    end
  end
end
