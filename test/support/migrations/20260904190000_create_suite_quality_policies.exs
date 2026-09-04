defmodule Aludel.Test.Repo.Migrations.CreateSuiteQualityPolicies do
  use Ecto.Migration

  def change do
    create table(:suite_quality_policies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :suite_id, references(:suites, type: :binary_id, on_delete: :delete_all), null: false
      add :version, :integer, null: false
      add :definition, :jsonb, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:suite_quality_policies, [:suite_id, :version])

    alter table(:suite_runs) do
      add :suite_policy_id,
          references(:suite_quality_policies, type: :binary_id, on_delete: :nilify_all)

      add :quality_policy_result, :jsonb
    end
  end
end
