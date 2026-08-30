defmodule Aludel.TestSupport.Migrations.AddDatasetProvenanceIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:test_cases, [:source_dataset_entry_id], concurrently: true)

    create unique_index(:test_cases, [:suite_id, :source_dataset_entry_id],
             concurrently: true,
             where: "source_dataset_entry_id IS NOT NULL"
           )
  end
end
