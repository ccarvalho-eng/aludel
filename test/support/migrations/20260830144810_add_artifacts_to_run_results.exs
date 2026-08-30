defmodule Aludel.TestSupport.Migrations.AddArtifactsToRunResults do
  use Ecto.Migration

  def change do
    alter table(:run_results) do
      add :artifacts, :map
    end
  end
end
