defmodule Aludel.Web.DatasetLive.RedTeamCatalogTest do
  use Aludel.Web.ConnCase, async: false

  import Aludel.DatasetsFixtures
  import Aludel.ProvidersFixtures
  import Phoenix.LiveViewTest

  alias Aludel.Datasets
  alias Aludel.RedTeam

  test "browses every curated case with its risk and judge guidance", %{conn: conn} do
    dataset = dataset_fixture()

    {:ok, view, _html} = live(conn, "/datasets/#{dataset.id}/red-team/catalog")

    assert has_element?(view, "#red-team-catalog")
    assert has_element?(view, "#red-team-case-direct-instruction-override", "critical")
    assert has_element?(view, "#red-team-case-direct-instruction-override", "prompt injection")
    assert has_element?(view, "#red-team-case-direct-instruction-override", "refusal")
    assert has_element?(view, "#red-team-case-fabricated-citation", "lunar dust")

    Enum.each(RedTeam.all(), fn template ->
      assert has_element?(view, "#red-team-case-#{template.id}[data-red-team-case]")
    end)

    assert has_element?(view, "a[href='/datasets/#{dataset.id}']", "Back to dataset")
  end

  test "materializes selected cases with an optional judge", %{conn: conn} do
    dataset = dataset_fixture()
    provider = provider_fixture()
    case_id = "direct-instruction-override"
    {:ok, view, _html} = live(conn, "/datasets/#{dataset.id}/red-team/catalog")

    view
    |> form("#red-team-materialization-form",
      materialization: %{
        case_ids: [case_id],
        variable: "request",
        judge_provider_id: provider.id,
        judge_threshold: "90"
      }
    )
    |> render_submit()

    assert has_element?(view, "#flash-info", "1 case created")
    assert has_element?(view, "#materialization-result", "1 created")
    assert has_element?(view, "#materialization-result", "0 already present")

    [entry] = Datasets.list_entries(dataset)
    template = RedTeam.fetch!(case_id)

    assert entry.variable_values == %{"request" => template.prompt}
    assert entry.metadata["red_team"]["case_id"] == case_id

    assert List.last(entry.assertions) == %{
             "type" => "rubric_judge",
             "template" => "refusal",
             "provider_id" => provider.id,
             "threshold" => 90.0
           }
  end

  test "reports idempotent skips without duplicating entries", %{conn: conn} do
    dataset = dataset_fixture()
    case_id = "fabricated-citation"
    {:ok, view, _html} = live(conn, "/datasets/#{dataset.id}/red-team/catalog")

    params = %{
      case_ids: [case_id],
      variable: "input",
      judge_provider_id: "",
      judge_threshold: "80"
    }

    view
    |> form("#red-team-materialization-form", materialization: params)
    |> render_submit()

    view
    |> form("#red-team-materialization-form", materialization: params)
    |> render_submit()

    assert has_element?(view, "#flash-info", "1 case already present")
    assert has_element?(view, "#materialization-result", "0 created")
    assert has_element?(view, "#materialization-result", "1 already present")
    assert length(Datasets.list_entries(dataset)) == 1
  end

  test "rejects empty, unknown, and invalid materialization options", %{conn: conn} do
    dataset = dataset_fixture()
    {:ok, view, _html} = live(conn, "/datasets/#{dataset.id}/red-team/catalog")

    render_hook(view, "materialize", %{
      "materialization" => %{
        "case_ids" => [],
        "variable" => "input",
        "judge_provider_id" => "",
        "judge_threshold" => "80"
      }
    })

    assert has_element?(view, "#materialization-errors", "Select at least one case")

    render_hook(view, "materialize", %{
      "materialization" => %{
        "case_ids" => ["missing-case"],
        "variable" => "invalid variable",
        "judge_provider_id" => "missing-provider",
        "judge_threshold" => "not-a-number"
      }
    })

    assert has_element?(view, "#materialization-errors", "Unknown catalog case")
    assert Datasets.list_entries(dataset) == []
  end
end
