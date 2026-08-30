defmodule Aludel.DatasetsTest do
  use Aludel.DataCase, async: true

  alias Aludel.Datasets
  alias Aludel.Datasets.{Dataset, DatasetEntry}
  alias Aludel.Evals

  describe "datasets" do
    test "creates and lists first-class datasets with metadata" do
      assert {:ok, %Dataset{} = dataset} =
               Datasets.create_dataset(%{
                 name: "Support conversations",
                 description: "Reusable support evaluation corpus",
                 metadata: %{"team" => "support", "locale" => "en"}
               })

      assert dataset.name == "Support conversations"
      assert dataset.metadata["team"] == "support"
      assert Datasets.list_datasets() == [dataset]
    end

    test "validates required names and JSON metadata" do
      assert {:error, changeset} = Datasets.create_dataset(%{name: ""})
      assert "can't be blank" in errors_on(changeset).name

      assert {:error, changeset} =
               Datasets.create_dataset(%{name: "Invalid", metadata: %{"pid" => self()}})

      assert "must be JSON-encodable" in errors_on(changeset).metadata
    end
  end

  describe "dataset entries" do
    setup do
      {:ok, dataset} = Datasets.create_dataset(%{name: "Conversation set"})
      %{dataset: dataset}
    end

    test "assigns stable positions and loads entries in order", %{dataset: dataset} do
      assert {:ok, first} =
               Datasets.create_entry(dataset, %{
                 name: "Single turn",
                 variable_values: %{"question" => "Hello"},
                 assertions: [%{"type" => "contains", "value" => "Hi"}]
               })

      assert {:ok, second} =
               Datasets.create_entry(dataset, %{
                 name: "Multi turn",
                 messages: [
                   %{"role" => "user", "content" => "I forgot my password"},
                   %{"role" => "assistant", "content" => "I can help with that"},
                   %{"role" => "user", "content" => "Send the reset steps"}
                 ],
                 assertions: [%{"type" => "contains", "value" => "reset"}],
                 metadata: %{"intent" => "password_reset"}
               })

      assert first.position == 0
      assert second.position == 1
      assert DatasetEntry.conversation_kind(first) == :single_turn
      assert DatasetEntry.conversation_kind(second) == :multi_turn

      loaded = Datasets.get_dataset_with_entries!(dataset.id)
      assert Enum.map(loaded.entries, & &1.id) == [first.id, second.id]

      assert Datasets.list_entries(dataset, metadata: %{"intent" => "password_reset"}) == [
               second
             ]
    end

    test "validates message roles, content, final user turn, and entry payload", %{
      dataset: dataset
    } do
      assert {:error, changeset} =
               Datasets.create_entry(dataset, %{
                 name: "Invalid role",
                 messages: [%{"role" => "tool", "content" => "result"}]
               })

      assert "contains an unsupported role" in errors_on(changeset).messages

      assert {:error, changeset} =
               Datasets.create_entry(dataset, %{
                 name: "Blank content",
                 messages: [%{"role" => "user", "content" => " "}]
               })

      assert "contains blank content" in errors_on(changeset).messages

      assert {:error, changeset} =
               Datasets.create_entry(dataset, %{
                 name: "Assistant final turn",
                 messages: [
                   %{"role" => "user", "content" => "Hello"},
                   %{"role" => "assistant", "content" => "Hi"}
                 ]
               })

      assert "must end with a user turn" in errors_on(changeset).messages

      assert {:error, changeset} =
               Datasets.create_entry(dataset, %{name: "Empty example"})

      assert "must include variables or messages" in errors_on(changeset).variable_values
    end
  end

  describe "populate_suite/2" do
    test "copies ordered entries with provenance without creating synchronization" do
      {:ok, dataset} = Datasets.create_dataset(%{name: "Reusable corpus"})

      {:ok, first} =
        Datasets.create_entry(dataset, %{
          name: "First",
          variable_values: %{"input" => "original"},
          assertions: [%{"type" => "contains", "value" => "first"}],
          metadata: %{"segment" => "a"}
        })

      {:ok, second} =
        Datasets.create_entry(dataset, %{
          name: "Second",
          messages: [%{"role" => "user", "content" => "Second question"}],
          assertions: [%{"type" => "contains", "value" => "second"}],
          metadata: %{"segment" => "b"}
        })

      suite = suite_fixture()

      assert {:ok, imported} = Datasets.populate_suite(dataset, suite)
      assert Enum.map(imported, & &1.source_dataset_entry_id) == [first.id, second.id]
      assert Enum.at(imported, 0).variable_values == %{"input" => "original"}

      assert Enum.at(imported, 1).messages == [
               %{"role" => "user", "content" => "Second question"}
             ]

      assert Enum.at(imported, 1).metadata == %{"segment" => "b"}

      assert {:ok, []} = Datasets.populate_suite(dataset, suite)
      assert length(Evals.get_suite_with_test_cases!(suite.id).test_cases) == 2

      assert {:ok, _entry} =
               Datasets.update_entry(first, %{variable_values: %{"input" => "changed"}})

      imported_first = Evals.get_test_case!(Enum.at(imported, 0).id)
      assert imported_first.variable_values == %{"input" => "original"}

      assert {:ok, _dataset} = Datasets.delete_dataset(dataset)

      retained = Evals.get_test_case!(imported_first.id)
      assert retained.source_dataset_entry_id == nil
      assert retained.variable_values == %{"input" => "original"}
    end
  end
end
