defmodule Aludel.Web.SuiteLive.PolicyTest do
  use Aludel.Web.ConnCase, async: false

  import Aludel.EvalsFixtures
  import Phoenix.LiveViewTest

  alias Aludel.Evals

  test "shows a validated starter policy and empty version history", %{conn: conn} do
    suite = suite_fixture()

    {:ok, view, _html} = live(conn, "/suites/#{suite.id}/policy")

    assert has_element?(view, "#quality-policy-form")
    assert has_element?(view, "#policy_definition")
    assert has_element?(view, "#policy-validation-valid", "1 rule")
    assert has_element?(view, "#policy-version-history", "No policy versions yet")
    assert has_element?(view, "a[href='/suites/#{suite.id}']", "Back to suite")
  end

  test "rejects malformed and invalid policy definitions without creating a version", %{
    conn: conn
  } do
    suite = suite_fixture()
    {:ok, view, _html} = live(conn, "/suites/#{suite.id}/policy")

    view
    |> form("#quality-policy-form", policy: %{definition: ~s({"schema_version":1,)})
    |> render_change()

    assert has_element?(view, "#policy-validation-errors", "Definition must be valid JSON")

    invalid_definition =
      Jason.encode!(%{
        "schema_version" => 1,
        "rules" => [%{"id" => "overall", "type" => "overall_pass_rate", "minimum" => 1.1}]
      })

    view
    |> form("#quality-policy-form", policy: %{definition: invalid_definition})
    |> render_submit()

    assert has_element?(
             view,
             "#policy-validation-errors",
             "minimum must be a number between 0 and 1"
           )

    assert Evals.list_suite_policies(suite) == []
  end

  test "creates immutable policy versions and keeps their definitions inspectable", %{conn: conn} do
    suite = suite_fixture()
    {:ok, view, _html} = live(conn, "/suites/#{suite.id}/policy")

    first_definition =
      policy_json([
        %{"id" => "overall", "type" => "overall_pass_rate", "minimum" => 0.9},
        %{"id" => "cost", "type" => "total_cost_usd", "maximum" => 0.5}
      ])

    view
    |> form("#quality-policy-form", policy: %{definition: first_definition})
    |> render_submit()

    assert has_element?(view, "#flash-info", "Policy version 1 created")
    assert has_element?(view, "#policy-version-1", "2 rules")

    second_definition =
      policy_json([
        %{"id" => "overall", "type" => "overall_pass_rate", "minimum" => 0.95}
      ])

    view
    |> form("#quality-policy-form", policy: %{definition: second_definition})
    |> render_submit()

    assert has_element?(view, "#flash-info", "Policy version 2 created")
    assert has_element?(view, "#policy-version-2", "Active")
    assert has_element?(view, "#policy-version-2", ~s("minimum": 0.95))
    assert has_element?(view, "#policy-version-1", ~s("maximum": 0.5))

    assert Enum.map(Evals.list_suite_policies(suite), & &1.version) == [2, 1]
  end

  defp policy_json(rules) do
    Jason.encode!(%{"schema_version" => 1, "rules" => rules}, pretty: true)
  end
end
