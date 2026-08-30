defmodule Aludel.TestSupport.Migrations.CreateDatasetsAndAddTestCaseProvenance do
  use Ecto.Migration

  def change do
    create table(:datasets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create table(:dataset_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :dataset_id, references(:datasets, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :variable_values, :map, null: false, default: %{}
      add :messages, {:array, :map}, null: false, default: []
      add :assertions, {:array, :map}, null: false, default: []
      add :metadata, :map, null: false, default: %{}
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:dataset_entries, [:dataset_id])
    create unique_index(:dataset_entries, [:dataset_id, :position])

    alter table(:test_cases) do
      add :source_dataset_entry_id,
          references(:dataset_entries, type: :binary_id, on_delete: :nilify_all)

      add :messages, {:array, :map}, null: false, default: []
      add :metadata, :map, null: false, default: %{}
    end
  end
end
