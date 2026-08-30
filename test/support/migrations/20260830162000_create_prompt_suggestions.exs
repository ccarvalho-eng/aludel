defmodule Aludel.TestRepo.Migrations.CreatePromptSuggestions do
  use Ecto.Migration

  def change do
    create table(:prompt_suggestions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :suggested_template, :text, null: false
      add :rationale, :text, null: false
      add :failure_summary, :map, null: false, default: %{}
      add :status, :string, null: false, default: "pending"

      add :prompt_id, references(:prompts, type: :binary_id, on_delete: :delete_all), null: false

      add :source_version_id,
          references(:prompt_versions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :accepted_version_id,
          references(:prompt_versions, type: :binary_id, on_delete: :nilify_all)

      add :suite_id, references(:suites, type: :binary_id, on_delete: :delete_all), null: false

      add :provider_id, references(:providers, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:prompt_suggestions, [:prompt_id, :status])

    create unique_index(
             :prompt_suggestions,
             [:source_version_id, :suite_id, :provider_id],
             name: :prompt_suggestions_one_pending_index,
             where: "status = 'pending'"
           )
  end
end
