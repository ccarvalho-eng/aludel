defmodule Aludel.Test.Repo.Migrations.IndexSuiteQualityPolicyRuns do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create_if_not_exists index(:suite_runs, [:suite_policy_id], concurrently: true)
  end
end
