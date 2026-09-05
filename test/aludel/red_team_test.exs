defmodule Aludel.RedTeamTest do
  use Aludel.DataCase, async: true

  alias Aludel.Datasets
  alias Aludel.Datasets.{Dataset, DatasetEntry}
  alias Aludel.RedTeam

  describe "catalog" do
    test "exposes stable, versioned cases across the supported risk categories" do
      cases = RedTeam.all()

      assert length(cases) == 7
      assert Enum.uniq_by(cases, & &1.id) == cases

      assert RedTeam.categories() == [
               :excessive_agency,
               :misinformation,
               :prompt_injection,
               :sensitive_information_disclosure,
               :system_prompt_leakage,
               :unsafe_assistance
             ]

      assert Enum.all?(cases, fn red_team_case ->
               red_team_case.version == 1 and
                 red_team_case.severity in [:high, :critical] and
                 byte_size(red_team_case.checksum) == 64 and
                 red_team_case.assertions == [
                   %{"type" => "not_contains", "value" => red_team_case.canary}
                 ]
             end)

      assert {:ok, direct_injection} = RedTeam.fetch("direct-instruction-override")
      assert direct_injection.category == :prompt_injection
      assert direct_injection.technique == :direct

      assert direct_injection.checksum ==
               "cf0ae25dcd2745693c5a2da322d4e48190969cf44cf2be05b048431a3f9527b7"

      assert :error = RedTeam.fetch("unknown-case")
    end
  end

  describe "materialize/2" do
    setup do
      {:ok, dataset} = Datasets.create_dataset(%{name: "Security regression set"})
      %{dataset: dataset}
    end

    test "creates executable entries with provenance and deduplication metadata", %{
      dataset: dataset
    } do
      assert {:ok, %{created: created, skipped: []}} = RedTeam.materialize(dataset)
      assert length(created) == 7
      assert Enum.map(created, & &1.position) == Enum.to_list(0..6)

      first = hd(created)
      template = RedTeam.all() |> Enum.find(&(&1.id == first.metadata["red_team"]["case_id"]))

      assert first.variable_values == %{"input" => template.prompt}
      assert first.assertions == template.assertions

      metadata = first.metadata["red_team"]
      assert metadata["catalog"] == "core"
      assert metadata["catalog_version"] == 1
      assert metadata["case_id"] == template.id
      assert metadata["case_version"] == template.version
      assert metadata["category"] == Atom.to_string(template.category)
      assert metadata["severity"] == Atom.to_string(template.severity)
      assert metadata["technique"] == Atom.to_string(template.technique)
      assert metadata["risk_reference"] == template.risk_reference
      assert metadata["recommended_judge"] == template.judge_template
      assert metadata["template_checksum"] == template.checksum
      assert byte_size(metadata["checksum"]) == 64

      assert metadata["deduplication_key"] ==
               "aludel:red_team:core@1:#{template.id}@#{template.version}:input"

      assert first.red_team_deduplication_key == metadata["deduplication_key"]

      assert metadata["provenance"] == %{
               "source" => "Aludel curated red-team catalog",
               "catalog" => "core",
               "version" => 1
             }

      assert {:ok, %{created: [], skipped: skipped}} = RedTeam.materialize(dataset)
      assert Enum.map(skipped, & &1.id) == Enum.map(created, & &1.id)
      assert length(Datasets.list_entries(dataset)) == 7
    end

    test "filters cases, supports another prompt variable, and adds rubric judges", %{
      dataset: dataset
    } do
      provider = provider_fixture()

      assert {:ok, %{created: [first, second], skipped: []}} =
               RedTeam.materialize(dataset,
                 categories: [:prompt_injection],
                 variable: "request",
                 judge_provider_id: provider.id,
                 judge_threshold: 90
               )

      assert first.variable_values == %{
               "request" => RedTeam.fetch!("direct-instruction-override").prompt
             }

      for entry <- [first, second] do
        assert [deterministic, judge] = entry.assertions
        assert deterministic["type"] == "not_contains"

        assert judge == %{
                 "type" => "rubric_judge",
                 "template" => entry.metadata["red_team"]["recommended_judge"],
                 "provider_id" => provider.id,
                 "threshold" => 90
               }
      end
    end

    test "rejects invalid selections without creating entries", %{dataset: dataset} do
      assert {:error, {:unknown_categories, [:not_a_category]}} =
               RedTeam.materialize(dataset, categories: [:not_a_category])

      assert {:error, {:unknown_case_ids, ["missing"]}} =
               RedTeam.materialize(dataset, case_ids: ["missing"])

      assert {:error, :invalid_variable} = RedTeam.materialize(dataset, variable: " ")

      assert {:error, :invalid_variable} =
               RedTeam.materialize(dataset, variable: <<255>>)

      assert {:error, :invalid_judge_provider_id} =
               RedTeam.materialize(dataset, judge_provider_id: "not-a-uuid")

      assert {:error, :invalid_judge_threshold} =
               RedTeam.materialize(dataset, judge_threshold: 101)

      assert {:error, :dataset_not_found} =
               RedTeam.materialize(%Dataset{id: Ecto.UUID.generate()})

      assert Datasets.list_entries(dataset) == []
    end

    test "ignores unrelated entries and arbitrary metadata shapes", %{dataset: dataset} do
      assert {:ok, unrelated} =
               Datasets.create_entry(dataset, %{
                 name: "Existing case",
                 variable_values: %{"input" => "Existing input"},
                 metadata: %{"red_team" => "user-defined label"}
               })

      assert {:ok, %{created: created, skipped: []}} =
               RedTeam.materialize(dataset, case_ids: ["direct-instruction-override"])

      assert Enum.map(Datasets.list_entries(dataset), & &1.id) == [unrelated.id, hd(created).id]
    end

    test "rolls back the complete selection when existing content conflicts", %{dataset: dataset} do
      template = RedTeam.fetch!("indirect-document-override")
      deduplication_key = "aludel:red_team:core@1:#{template.id}@#{template.version}:input"

      assert {:ok, %{created: [entry]}} =
               RedTeam.materialize(dataset, case_ids: [template.id])

      conflicting_metadata =
        put_in(entry.metadata, ["red_team", "checksum"], String.duplicate("0", 64))

      assert {:ok, conflicting_entry} =
               Datasets.update_entry(entry, %{metadata: conflicting_metadata})

      assert {:error, {:deduplication_conflict, ^deduplication_key}} =
               RedTeam.materialize(dataset, categories: [:prompt_injection])

      assert Datasets.list_entries(dataset) == [conflicting_entry]
    end

    test "rejects judge configuration drift under the same deduplication key", %{
      dataset: dataset
    } do
      first_provider = provider_fixture()
      second_provider = provider_fixture()

      assert {:ok, %{created: [_entry]}} =
               RedTeam.materialize(dataset,
                 case_ids: ["direct-instruction-override"],
                 judge_provider_id: first_provider.id
               )

      expected_key = "aludel:red_team:core@1:direct-instruction-override@1:input"

      assert {:error, {:deduplication_conflict, ^expected_key}} =
               RedTeam.materialize(dataset,
                 case_ids: ["direct-instruction-override"],
                 judge_provider_id: second_provider.id
               )
    end

    test "rejects payload tampering even when checksum metadata is unchanged", %{
      dataset: dataset
    } do
      assert {:ok, %{created: [entry]}} =
               RedTeam.materialize(dataset, case_ids: ["direct-instruction-override"])

      assert {:ok, _tampered} =
               Datasets.update_entry(entry, %{
                 variable_values: %{"input" => "Replaced adversarial input"}
               })

      expected_key = "aludel:red_team:core@1:direct-instruction-override@1:input"

      assert {:error, {:deduplication_conflict, ^expected_key}} =
               RedTeam.materialize(dataset, case_ids: ["direct-instruction-override"])
    end

    test "enforces deduplication keys at the database boundary", %{dataset: dataset} do
      assert {:ok, %{created: [entry]}} =
               RedTeam.materialize(dataset, case_ids: ["direct-instruction-override"])

      duplicate = %DatasetEntry{
        dataset_id: dataset.id,
        red_team_deduplication_key: entry.red_team_deduplication_key
      }

      changeset =
        DatasetEntry.changeset(duplicate, %{
          name: "Duplicate source",
          variable_values: %{"input" => "Different input"},
          metadata: entry.metadata,
          position: 1
        })

      assert {:error, changeset} = Repo.insert(changeset)

      assert "has already been taken" in errors_on(changeset).red_team_deduplication_key
    end

    test "supports the longest valid variable without exceeding the database key", %{
      dataset: dataset
    } do
      variable = "v" <> String.duplicate("a", 199)

      assert {:ok, %{created: [entry], skipped: []}} =
               RedTeam.materialize(dataset,
                 case_ids: ["direct-instruction-override"],
                 variable: variable
               )

      assert byte_size(entry.red_team_deduplication_key) <= 255

      assert {:ok, %{created: [], skipped: [skipped]}} =
               RedTeam.materialize(dataset,
                 case_ids: ["direct-instruction-override"],
                 variable: variable
               )

      assert skipped.id == entry.id
    end
  end
end
