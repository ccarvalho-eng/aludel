defmodule Aludel.Test.Repo.Migrations.AddRedTeamDeduplicationKey do
  use Ecto.Migration

  def change do
    alter table(:dataset_entries) do
      add :red_team_deduplication_key, :string
    end
  end
end
