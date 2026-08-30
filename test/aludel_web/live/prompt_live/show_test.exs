defmodule Aludel.Web.PromptLive.ShowTest do
  use Aludel.Web.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Aludel.PromptsFixtures

  alias Aludel.Prompts

  describe "show prompt" do
    test "renders prompt details", %{conn: conn} do
      prompt =
        prompt_fixture(%{
          name: "Test Prompt",
          description: "Test description",
          tags: ["test", "example"]
        })

      {:ok, _view, html} = live(conn, "/prompts/#{prompt.id}")

      assert html =~ "Test Prompt"
      assert html =~ "Test description"
      assert html =~ "test"
      assert html =~ "example"
    end

    test "displays all versions ordered by version desc", %{conn: conn} do
      prompt = prompt_fixture(%{name: "Versioned Prompt"})

      # Create versions
      {:ok, v1} = Prompts.create_prompt_version(prompt, "Version 1 template")
      {:ok, v2} = Prompts.create_prompt_version(prompt, "Version 2 template")
      {:ok, v3} = Prompts.create_prompt_version(prompt, "Version 3 template")

      {:ok, _view, html} = live(conn, "/prompts/#{prompt.id}")

      # Only the latest version template is displayed in the main content
      assert html =~ "Version 3 template"

      # All version numbers are visible in the history sidebar
      assert html =~ "v#{v1.version}"
      assert html =~ "v#{v2.version}"
      assert html =~ "v#{v3.version}"
    end

    test "places version history to the right of prompt details on desktop", %{conn: conn} do
      prompt = prompt_fixture(%{name: "Versioned Prompt"})
      {:ok, _version} = Prompts.create_prompt_version(prompt, "Version template")

      {:ok, view, _html} = live(conn, "/prompts/#{prompt.id}")

      assert has_element?(view, "#prompt-details-content[class~='md:col-start-1']")
      assert has_element?(view, "#prompt-version-history[class~='md:col-start-2']")
    end

    test "displays version variables", %{conn: conn} do
      prompt = prompt_fixture(%{name: "Variable Test"})

      {:ok, _version} =
        Prompts.create_prompt_version(
          prompt,
          "Hello {{name}}, welcome to {{topic}}"
        )

      {:ok, _view, html} = live(conn, "/prompts/#{prompt.id}")

      assert html =~ "name"
      assert html =~ "topic"
    end

    test "shows edit button linking to edit page", %{conn: conn} do
      prompt = prompt_fixture(%{name: "Editable Prompt"})

      {:ok, view, _html} = live(conn, "/prompts/#{prompt.id}")

      assert has_element?(view, "a[href=\"/prompts/#{prompt.id}/edit\"]")
    end

    test "shows back button to index", %{conn: conn} do
      prompt = prompt_fixture(%{name: "Test Prompt"})

      {:ok, view, _html} = live(conn, "/prompts/#{prompt.id}")

      assert has_element?(view, "a[href=\"/prompts\"]")
    end

    test "raises 404 for non-existent prompt", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, "/prompts/#{fake_id}")
      end
    end

    test "displays message when prompt has no versions", %{conn: conn} do
      prompt = prompt_fixture(%{name: "No Versions"})

      {:ok, _view, html} = live(conn, "/prompts/#{prompt.id}")

      assert html =~ "No versions"
    end

    test "can navigate to create run", %{conn: conn} do
      prompt = prompt_fixture(%{name: "Test Prompt"})
      {:ok, version} = Prompts.create_prompt_version(prompt, "Hello {{name}}")

      {:ok, view, _html} = live(conn, "/prompts/#{prompt.id}")

      assert has_element?(
               view,
               "a[href*='/runs/new'][href*='version=#{version.id}']"
             )
    end

    test "shows evolution tab link", %{conn: conn} do
      prompt = prompt_fixture(%{name: "Test Prompt"})

      {:ok, view, _html} = live(conn, "/prompts/#{prompt.id}")

      assert has_element?(view, "a[href=\"/prompts/#{prompt.id}/evolution\"]")
    end

    test "compares the selected version with its previous version", %{conn: conn} do
      prompt = prompt_fixture(%{name: "Comparable Prompt"})

      {:ok, _v1} =
        Prompts.create_prompt_version(prompt, "System prompt\nHello {{name}} from {{legacy}}")

      {:ok, _v2} =
        Prompts.create_prompt_version(prompt, "System prompt\nHi {{name}} about {{topic}}")

      {:ok, view, _html} = live(conn, "/prompts/#{prompt.id}")

      assert has_element?(view, "#compare-version-button")

      view
      |> element("#compare-version-button")
      |> render_click()

      assert has_element?(view, "#prompt-version-diff")

      assert has_element?(
               view,
               "#template-diff-lines [data-diff-kind='del']",
               "Hello {{name}} from {{legacy}}"
             )

      assert has_element?(
               view,
               "#template-diff-lines [data-diff-kind='ins']",
               "Hi {{name}} about {{topic}}"
             )

      assert has_element?(view, "#variable-diff [data-variable-change='added']", "topic")
      assert has_element?(view, "#variable-diff [data-variable-change='removed']", "legacy")

      view
      |> element("#close-version-diff")
      |> render_click()

      assert has_element?(view, "#prompt-version-content")
      refute has_element?(view, "#prompt-version-diff")
    end

    test "offers an arbitrary comparison for the oldest version", %{conn: conn} do
      prompt = prompt_fixture(%{name: "Oldest Prompt"})
      {:ok, oldest_version} = Prompts.create_prompt_version(prompt, "Original")
      {:ok, _latest_version} = Prompts.create_prompt_version(prompt, "Updated")

      {:ok, view, _html} = live(conn, "/prompts/#{prompt.id}")

      view
      |> element("#prompt-version-#{oldest_version.id}")
      |> render_click()

      assert has_element?(view, "#compare-version-button", "Compare with v2")
    end

    test "compares arbitrary non-adjacent versions", %{conn: conn} do
      prompt = prompt_fixture(%{name: "Long-lived Prompt"})
      {:ok, v1} = Prompts.create_prompt_version(prompt, "Original {{name}}")
      {:ok, _v2} = Prompts.create_prompt_version(prompt, "Middle {{name}}")
      {:ok, _v3} = Prompts.create_prompt_version(prompt, "Latest {{name}} and {{topic}}")

      {:ok, view, _html} = live(conn, "/prompts/#{prompt.id}")

      view
      |> form("#comparison-version-form", comparison: %{version_id: v1.id})
      |> render_change()

      assert has_element?(view, "#compare-version-button", "Compare with v1")

      view
      |> element("#compare-version-button")
      |> render_click()

      assert has_element?(view, "#prompt-version-diff", "v1 to v3")
      assert has_element?(view, "#template-diff-lines [data-diff-kind='del']", "Original")
      assert has_element?(view, "#template-diff-lines [data-diff-kind='ins']", "Latest")
    end
  end
end
