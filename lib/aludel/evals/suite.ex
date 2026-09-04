defmodule Aludel.Evals.Suite do
  @moduledoc """
  Schema for evaluation test suites.

  A suite groups test cases together for a specific prompt, allowing
  systematic testing across multiple scenarios.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Aludel.Evals.{SuitePolicy, SuiteRun, TestCase}
  alias Aludel.Projects.Project
  alias Aludel.Prompts.Prompt
  alias Ecto.Changeset

  @type t :: %__MODULE__{}

  @required_fields ~w(name prompt_id)a
  @optional_fields ~w(project_id)a

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "suites" do
    field(:name, :string)

    belongs_to(:project, Project)
    belongs_to(:prompt, Prompt)
    has_many(:test_cases, TestCase)
    has_many(:quality_policies, SuitePolicy)
    has_many(:suite_runs, SuiteRun)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a suite.

  Validates that name and prompt_id are present.
  """
  @spec changeset(t(), map()) :: Changeset.t()
  def changeset(suite, attrs) do
    suite
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
