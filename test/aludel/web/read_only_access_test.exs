defmodule Aludel.Web.ReadOnlyAccessTest do
  use Aludel.Web.ConnCase, async: false

  import Aludel.ProvidersFixtures

  alias Aludel.Providers

  test "blocks direct mutation events", %{conn: conn} do
    provider = provider_fixture(%{name: "Protected Provider"})
    {:ok, view, html} = live(conn, "/read-only/providers")

    assert html =~ "Read-only mode is active"
    assert render_click(view, "delete", %{"id" => provider.id}) =~ "read-only"
    assert Providers.get_provider!(provider.id).id == provider.id
  end

  test "keeps inspection events available", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/read-only/")

    html = render_click(view, "toggle_cost_view", %{})

    assert html =~ "Read-only mode is active"
    refute html =~ "This dashboard is read-only. Changes and model requests are disabled."
  end
end
