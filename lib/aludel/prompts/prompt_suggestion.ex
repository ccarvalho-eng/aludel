defmodule Aludel.Prompts.PromptSuggestion do
  @moduledoc """
  A failure-grounded prompt revision awaiting an explicit human decision.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Aludel.Evals.Suite
  alias Aludel.Prompts.{Prompt, PromptVersion}
  alias Aludel.Providers.Provider
  alias Ecto.Changeset

  @type t :: %__MODULE__{}

  @required_fields ~w(
    prompt_id
    source_version_id
    suite_id
    provider_id
    suggested_template
    rationale
  )a
  @optional_fields ~w(failure_summary status accepted_version_id)a

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "prompt_suggestions" do
    field :suggested_template, :string
    field :rationale, :string
    field :failure_summary, :map, default: %{}
    field :status, Ecto.Enum, values: [:pending, :accepted, :dismissed], default: :pending

    belongs_to :prompt, Prompt
    belongs_to :source_version, PromptVersion
    belongs_to :accepted_version, PromptVersion
    belongs_to :suite, Suite
    belongs_to :provider, Provider

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for a generated prompt suggestion and its review state.
  """
  @spec changeset(t(), map()) :: Changeset.t()
  def changeset(suggestion, attrs) do
    suggestion
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:suggested_template, min: 1)
    |> validate_length(:rationale, min: 1)
    |> foreign_key_constraint(:prompt_id)
    |> foreign_key_constraint(:source_version_id)
    |> foreign_key_constraint(:accepted_version_id)
    |> foreign_key_constraint(:suite_id)
    |> foreign_key_constraint(:provider_id)
    |> unique_constraint([:source_version_id, :suite_id, :provider_id],
      name: :prompt_suggestions_one_pending_index
    )
  end
end
