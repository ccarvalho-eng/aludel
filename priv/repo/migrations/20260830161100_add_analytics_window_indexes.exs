defmodule Aludel.Repo.Migrations.AddAnalyticsWindowIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create index(:runs, [:inserted_at], concurrently: true)
    create index(:suite_runs, [:inserted_at], concurrently: true)
    create index(:suite_runs, [:prompt_version_id, :inserted_at], concurrently: true)
  end

  def down do
    drop index(:suite_runs, [:prompt_version_id, :inserted_at], concurrently: true)
    drop index(:suite_runs, [:inserted_at], concurrently: true)
    drop index(:runs, [:inserted_at], concurrently: true)
  end
end
