defmodule Aludel.Web.DatasetLive.IndexTest do
  use Aludel.Web.ConnCase, async: false

  import Aludel.DatasetsFixtures
  import Phoenix.LiveViewTest

  alias Aludel.Datasets

  test "renders the empty state and validates dataset creation", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/datasets")

    assert has_element?(view, "#datasets-empty")
    assert has_element?(view, "#dataset-form")

    view
    |> form("#dataset-form", dataset: %{name: "", metadata_json: "not-json"})
    |> render_submit()

    assert has_element?(view, "#dataset-name-error", "can't be blank")
    assert has_element?(view, "#dataset-metadata-json-error", "must be a JSON object")
    assert Datasets.list_datasets() == []
  end

  test "creates, links, and deletes a dataset without a reload", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/datasets")

    view
    |> form("#dataset-form",
      dataset: %{
        name: "Billing conversations",
        description: "Production-shaped billing questions",
        metadata_json: ~s({"team":"billing"})
      }
    )
    |> render_submit()

    [dataset] = Datasets.list_datasets()
    assert has_element?(view, "#dataset-#{dataset.id}")
    assert has_element?(view, "#dataset-#{dataset.id} a[href='/datasets/#{dataset.id}']")
    refute has_element?(view, "#datasets-empty")

    view
    |> element("#delete-dataset-#{dataset.id}")
    |> render_click()

    refute has_element?(view, "#dataset-#{dataset.id}")
    assert has_element?(view, "#datasets-empty")
    assert Datasets.list_datasets() == []
  end

  test "lists existing datasets and exposes datasets in navigation", %{conn: conn} do
    dataset = dataset_fixture()

    {:ok, view, _html} = live(conn, "/datasets")

    assert has_element?(view, "#dataset-#{dataset.id}", dataset.name)
    assert has_element?(view, "nav a[href='/datasets']", "Datasets")
  end

  test "handles a malformed delete id without changing datasets", %{conn: conn} do
    dataset = dataset_fixture()
    {:ok, view, _html} = live(conn, "/datasets")

    render_hook(view, "delete", %{"id" => "not-a-dataset-id"})

    assert has_element?(view, "#flash-error", "Dataset not found")
    assert Datasets.get_dataset!(dataset.id)
  end
end
