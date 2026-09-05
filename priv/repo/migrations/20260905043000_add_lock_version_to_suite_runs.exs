defmodule Aludel.Repo.Migrations.AddLockVersionToSuiteRuns do
  use Ecto.Migration

  def change do
    alter table(:suite_runs) do
      add :lock_version, :integer, null: false, default: 1
    end
  end
end
