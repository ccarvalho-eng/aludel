defmodule Aludel.Repo.Migrations.AddRedTeamDeduplicationIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    drop_index()

    create unique_index(
             :dataset_entries,
             [:dataset_id, :red_team_deduplication_key],
             name: :dataset_entries_red_team_deduplication_index,
             concurrently: true,
             where: "red_team_deduplication_key IS NOT NULL"
           )
  end

  def down do
    drop_index()
  end

  defp drop_index do
    drop_if_exists index(:dataset_entries, [:dataset_id, :red_team_deduplication_key],
                     name: :dataset_entries_red_team_deduplication_index,
                     concurrently: true
                   )
  end
end
