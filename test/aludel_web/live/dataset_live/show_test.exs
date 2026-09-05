defmodule Aludel.Web.DatasetLive.ShowTest do
  use Aludel.Web.ConnCase, async: false

  import Aludel.DatasetsFixtures
  import Phoenix.LiveViewTest

  alias Aludel.Datasets

  test "updates dataset details and renders the entry empty state", %{conn: conn} do
    dataset = dataset_fixture()
    {:ok, view, _html} = live(conn, "/datasets/#{dataset.id}")

    assert has_element?(view, "#dataset-entries-empty")

    assert has_element?(
             view,
             "a[href='/datasets/#{dataset.id}/red-team/catalog']",
             "Add red-team cases"
           )

    view
    |> form("#dataset-details-form",
      dataset: %{
        name: "Updated conversations",
        description: "Updated description",
        metadata_json: ~s({"team":"success"})
      }
    )
    |> render_submit()

    updated = Datasets.get_dataset!(dataset.id)
    assert updated.name == "Updated conversations"
    assert updated.metadata == %{"team" => "success"}
    assert has_element?(view, "#dataset-title", "Updated conversations")
  end

  test "rejects malformed JSON and conversations without a final user turn", %{conn: conn} do
    dataset = dataset_fixture()
    {:ok, view, _html} = live(conn, "/datasets/#{dataset.id}")

    view
    |> form("#dataset-entry-form",
      entry: %{
        name: "Broken entry",
        variable_values_json: "{}",
        messages_json: "not-json",
        assertions_json: "[]",
        metadata_json: "{}"
      }
    )
    |> render_submit()

    assert has_element?(view, "#entry-messages-json-error", "must be a JSON array")

    view
    |> form("#dataset-entry-form",
      entry: %{
        name: "Assistant-final entry",
        variable_values_json: "{}",
        messages_json:
          ~s([{"role":"user","content":"Hi"},{"role":"assistant","content":"Hello"}]),
        assertions_json: "[]",
        metadata_json: "{}"
      }
    )
    |> render_submit()

    assert has_element?(view, "#entry-messages-json-error", "must end with a user turn")
    assert Datasets.list_entries(dataset) == []
  end

  test "creates and renders a multi-turn entry with metadata", %{conn: conn} do
    dataset = dataset_fixture()
    {:ok, view, _html} = live(conn, "/datasets/#{dataset.id}")

    view
    |> form("#dataset-entry-form",
      entry: %{
        name: "Escalated refund",
        variable_values_json: ~s({"account":"A-42"}),
        messages_json:
          ~s([{"role":"system","content":"Be precise."},{"role":"assistant","content":"How can I help?"},{"role":"user","content":"Refund order 42."}]),
        assertions_json: ~s([{"type":"contains","value":"refund"}]),
        metadata_json: ~s({"locale":"en","tier":"pro"})
      }
    )
    |> render_submit()

    [entry] = Datasets.list_entries(dataset)
    assert has_element?(view, "#dataset-entry-#{entry.id}", "Escalated refund")
    assert has_element?(view, "#dataset-entry-message-#{entry.id}-0", "system")
    assert has_element?(view, "#dataset-entry-message-#{entry.id}-2", "Refund order 42.")
    assert has_element?(view, "#dataset-entry-metadata-#{entry.id}", "locale")
    refute has_element?(view, "#dataset-entries-empty")
  end

  test "creates a single-turn variables entry without conversation messages", %{conn: conn} do
    dataset = dataset_fixture()
    {:ok, view, _html} = live(conn, "/datasets/#{dataset.id}")

    view
    |> form("#dataset-entry-form",
      entry: %{
        name: "Single-turn greeting",
        variable_values_json: ~s({"name":"Ada"}),
        messages_json: "[]",
        assertions_json: ~s([{"type":"contains","value":"Ada"}]),
        metadata_json: ~s({"shape":"single-turn"})
      }
    )
    |> render_submit()

    [entry] = Datasets.list_entries(dataset)
    assert entry.messages == []
    assert has_element?(view, "#dataset-entry-#{entry.id}", "Single-turn greeting")
    refute has_element?(view, "#dataset-entry-message-#{entry.id}-0")
  end

  test "filters entries by metadata and deletes an entry", %{conn: conn} do
    dataset = dataset_fixture()
    english = dataset_entry_fixture(%{dataset: dataset, metadata: %{"locale" => "en"}})

    _portuguese =
      dataset_entry_fixture(%{
        dataset: dataset,
        name: "Portuguese",
        metadata: %{"locale" => "pt-BR"}
      })

    {:ok, view, _html} = live(conn, "/datasets/#{dataset.id}")

    view
    |> form("#dataset-entry-filter-form", filter: %{metadata_json: ~s({"locale":"en"})})
    |> render_submit()

    assert has_element?(view, "#dataset-entry-#{english.id}")
    assert has_element?(view, "#dataset-entry-count", "1 entry")
    refute has_element?(view, "#dataset-entry-filter-error")

    view
    |> element("#delete-dataset-entry-#{english.id}")
    |> render_click()

    assert has_element?(view, "#dataset-entries-empty")
    assert Datasets.list_entries(dataset, metadata: %{"locale" => "en"}) == []
  end

  test "shows a stable filter error for invalid metadata JSON", %{conn: conn} do
    dataset = dataset_fixture()
    {:ok, view, _html} = live(conn, "/datasets/#{dataset.id}")

    view
    |> form("#dataset-entry-filter-form", filter: %{metadata_json: "[]"})
    |> render_submit()

    assert has_element?(view, "#dataset-entry-filter-error", "must be a JSON object")
  end

  test "does not delete entries owned by another dataset", %{conn: conn} do
    dataset = dataset_fixture()
    other_entry = dataset_entry_fixture()
    {:ok, view, _html} = live(conn, "/datasets/#{dataset.id}")

    render_hook(view, "delete_entry", %{"id" => other_entry.id})

    assert has_element?(view, "#flash-error", "Dataset entry not found")
    other_dataset = Datasets.get_dataset!(other_entry.dataset_id)
    assert Datasets.get_entry(other_dataset, other_entry.id)
  end
end
