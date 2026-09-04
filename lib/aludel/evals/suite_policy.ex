defmodule Aludel.Evals.SuitePolicy do
  @moduledoc """
  Immutable version of a quality policy attached to an evaluation suite.

  Creating a new policy produces the next suite-local version. Existing suite
  runs keep their policy association so retries and exports use the same
  evaluation contract that was active when the run started.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Aludel.Evals.QualityPolicy
  alias Aludel.Evals.Suite
  alias Aludel.Evals.SuiteRun
  alias Ecto.Changeset

  @type t :: %__MODULE__{}

  @required_fields ~w(suite_id version definition)a

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "suite_quality_policies" do
    field :version, :integer
    field :definition, :map

    belongs_to :suite, Suite
    has_many :suite_runs, SuiteRun

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for a versioned suite policy.
  """
  @spec changeset(t(), map()) :: Changeset.t()
  def changeset(policy, attrs) do
    policy
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_number(:version, greater_than: 0)
    |> validate_definition()
    |> foreign_key_constraint(:suite_id)
    |> unique_constraint([:suite_id, :version])
  end

  defp validate_definition(changeset) do
    validate_change(changeset, :definition, fn :definition, definition ->
      case QualityPolicy.validate(definition) do
        :ok -> []
        {:error, _errors} -> [definition: "is invalid"]
      end
    end)
  end
end
