defmodule Aludel.Web.ProviderLive.IndexTest do
  use Aludel.Web.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Aludel.ProvidersFixtures

  describe "provider list" do
    test "mounts successfully", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/providers")

      assert has_element?(view, "h1", "Providers")
    end

    test "displays list of providers", %{conn: conn} do
      provider1 = provider_fixture(%{name: "OpenAI GPT-4"})
      provider2 = provider_fixture(%{name: "Claude Sonnet"})

      {:ok, view, _html} = live(conn, "/providers")

      assert has_element?(view, "#providers-#{provider1.id}", "OpenAI GPT-4")
      assert has_element?(view, "#providers-#{provider2.id}", "Claude Sonnet")
    end

    test "shows new provider button", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/providers")

      assert has_element?(view, "#new-provider-btn", "New Provider")
    end

    test "displays provider details", %{conn: conn} do
      provider =
        provider_fixture(%{
          name: "Test Provider",
          provider: :openai,
          model: "gpt-4o"
        })

      {:ok, view, _html} = live(conn, "/providers")

      assert has_element?(view, "#providers-#{provider.id}", "Test Provider")
      assert has_element?(view, "#providers-#{provider.id}", "gpt-4o")
    end

    test "displays Google provider with Google icon", %{conn: conn} do
      provider =
        provider_fixture(%{
          name: "Gemini Flash",
          provider: :google,
          model: "gemini-2.5-flash"
        })

      {:ok, view, _html} = live(conn, "/providers")

      assert has_element?(view, "#providers-#{provider.id}", "Gemini Flash")
      assert has_element?(view, ".provider-icon-google")
    end

    test "displays xAI with its icon and Groq with the fallback icon", %{conn: conn} do
      xai = provider_fixture(%{name: "xAI Grok", provider: :xai, model: "grok-4"})

      groq =
        provider_fixture(%{
          name: "Groq Llama",
          provider: :groq,
          model: "llama-3.3-70b-versatile"
        })

      {:ok, view, _html} = live(conn, "/providers")

      assert has_element?(view, "#providers-#{xai.id} .provider-icon-xai")
      assert has_element?(view, "#providers-#{groq.id} .provider-icon-fallback-groq")
    end
  end

  describe "delete functionality" do
    test "deletes provider successfully", %{conn: conn} do
      provider = provider_fixture(%{name: "Delete Me"})

      {:ok, view, _html} = live(conn, "/providers")

      render_click(view, "delete", %{"id" => provider.id})

      assert render(view) =~ "Provider deleted successfully"
      refute has_element?(view, "#providers-#{provider.id}")
    end

    test "refreshes provider list after deletion", %{conn: conn} do
      provider1 = provider_fixture(%{name: "Provider 1"})
      provider2 = provider_fixture(%{name: "Provider 2"})

      {:ok, view, _html} = live(conn, "/providers")

      assert has_element?(view, "#providers-#{provider1.id}", "Provider 1")
      assert has_element?(view, "#providers-#{provider2.id}", "Provider 2")

      render_click(view, "delete", %{"id" => provider1.id})

      refute has_element?(view, "#providers-#{provider1.id}")
      assert has_element?(view, "#providers-#{provider2.id}", "Provider 2")
    end
  end
end
