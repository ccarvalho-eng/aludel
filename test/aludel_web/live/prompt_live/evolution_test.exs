defmodule Aludel.Web.PromptLive.EvolutionTest do
  use Aludel.Web.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Aludel.PromptsFixtures
  import Aludel.ProvidersFixtures
  import Aludel.EvalsFixtures

  alias Aludel.Prompts

  describe "evolution page" do
    test "renders evolution tab for prompt", %{conn: conn} do
      prompt = prompt_fixture(%{name: "Evolution Test"})

      {:ok, _view, html} = live(conn, "/prompts/#{prompt.id}/evolution")

      assert html =~ "Evolution Test"
      assert html =~ "Evolution"
    end

    test "displays message when no versions exist", %{conn: conn} do
      prompt = prompt_fixture()

      {:ok, _view, html} = live(conn, "/prompts/#{prompt.id}/evolution")

      assert html =~ "No versions"
    end

    test "displays version metrics", %{conn: conn} do
      prompt = prompt_fixture(%{name: "Metrics Test"})
      {:ok, _v1} = Prompts.create_prompt_version(prompt, "Version 1 {{var}}")
      {:ok, _v2} = Prompts.create_prompt_version(prompt, "Version 2 {{var}}")

      {:ok, _view, html} = live(conn, "/prompts/#{prompt.id}/evolution")

      assert html =~ "v1"
      assert html =~ "v2"
    end

    test "displays provider breakdown when available", %{conn: conn} do
      prompt = prompt_fixture()
      provider = provider_fixture(%{name: "Test Provider"})
      {:ok, version} = Prompts.create_prompt_version(prompt, "Test {{var}}")
      suite = suite_fixture(%{prompt_id: prompt.id})

      {:ok, _sr} =
        Aludel.Evals.create_suite_run(%{
          suite_id: suite.id,
          prompt_version_id: version.id,
          provider_id: provider.id,
          passed: 8,
          failed: 2
        })

      {:ok, _view, html} = live(conn, "/prompts/#{prompt.id}/evolution")

      assert html =~ "Test Provider"
      assert html =~ "80.0%"
    end
  end

  describe "chart functionality" do
    test "assigns chart data on mount", %{conn: conn} do
      prompt = prompt_fixture()

      {:ok, view, _html} = live(conn, "/prompts/#{prompt.id}/evolution")

      state = :sys.get_state(view.pid)
      socket = state.socket

      assert socket.assigns.chart_data
      assert socket.assigns.view_mode == :overall
      assert socket.assigns.show_breakdown_sidebar == false
    end

    test "toggles view mode from overall to by_provider", %{conn: conn} do
      prompt = prompt_fixture()

      {:ok, view, _html} = live(conn, "/prompts/#{prompt.id}/evolution")

      state = :sys.get_state(view.pid)
      socket = state.socket
      assert socket.assigns.view_mode == :overall

      render_click(view, "toggle_view_mode")

      state = :sys.get_state(view.pid)
      socket = state.socket
      assert socket.assigns.view_mode == :by_provider
    end

    test "toggles view mode from by_provider to overall", %{conn: conn} do
      prompt = prompt_fixture()

      {:ok, view, _html} = live(conn, "/prompts/#{prompt.id}/evolution")

      # Toggle to by_provider first
      render_click(view, "toggle_view_mode")

      state = :sys.get_state(view.pid)
      socket = state.socket
      assert socket.assigns.view_mode == :by_provider

      # Toggle back to overall
      render_click(view, "toggle_view_mode")

      state = :sys.get_state(view.pid)
      socket = state.socket
      assert socket.assigns.view_mode == :overall
    end

    test "handles chart-mounted event", %{conn: conn} do
      prompt = prompt_fixture()

      {:ok, view, _html} = live(conn, "/prompts/#{prompt.id}/evolution")

      # Should not raise - chart-mounted sends update-chart event
      render_hook(view, "chart-mounted", %{})
    end

    test "toggles breakdown sidebar", %{conn: conn} do
      prompt = prompt_fixture()

      {:ok, view, _html} = live(conn, "/prompts/#{prompt.id}/evolution")

      state = :sys.get_state(view.pid)
      socket = state.socket
      assert socket.assigns.show_breakdown_sidebar == false

      render_click(view, "toggle_breakdown_sidebar")

      state = :sys.get_state(view.pid)
      socket = state.socket
      assert socket.assigns.show_breakdown_sidebar == true

      # Toggle back
      render_click(view, "toggle_breakdown_sidebar")

      state = :sys.get_state(view.pid)
      socket = state.socket
      assert socket.assigns.show_breakdown_sidebar == false
    end
  end

  describe "metrics display" do
    test "shows metrics in descending order (newest first)", %{conn: conn} do
      prompt = prompt_fixture()
      {:ok, _v1} = Prompts.create_prompt_version(prompt, "Version 1 {{var}}")
      {:ok, _v2} = Prompts.create_prompt_version(prompt, "Version 2 {{var}}")
      {:ok, _v3} = Prompts.create_prompt_version(prompt, "Version 3 {{var}}")

      {:ok, view, _html} = live(conn, "/prompts/#{prompt.id}/evolution")

      state = :sys.get_state(view.pid)
      socket = state.socket

      # Metrics should be in reverse order
      assert length(socket.assigns.metrics) == 3
      assert Enum.at(socket.assigns.metrics, 0).version_number == 3
      assert Enum.at(socket.assigns.metrics, 1).version_number == 2
      assert Enum.at(socket.assigns.metrics, 2).version_number == 1
    end

    test "includes cost and latency in metrics", %{conn: conn} do
      prompt = prompt_fixture()
      provider = provider_fixture()
      {:ok, version} = Prompts.create_prompt_version(prompt, "Test {{var}}")
      suite = suite_fixture(%{prompt_id: prompt.id})

      {:ok, _sr} =
        Aludel.Evals.create_suite_run(%{
          suite_id: suite.id,
          prompt_version_id: version.id,
          provider_id: provider.id,
          passed: 5,
          failed: 0,
          avg_cost_usd: Decimal.new("0.005"),
          avg_latency_ms: 450,
          avg_score: Decimal.new("82.5")
        })

      {:ok, view, _html} = live(conn, "/prompts/#{prompt.id}/evolution")

      state = :sys.get_state(view.pid)
      socket = state.socket

      [metric] = socket.assigns.metrics
      assert Decimal.equal?(metric.avg_cost_usd, Decimal.new("0.005"))
      assert metric.avg_latency_ms == 450
      assert Decimal.equal?(metric.avg_score, Decimal.new("82.5"))
      assert socket.assigns.chart_data.overall.scores == [82.5]
    end

    test "renders efficiency and stability signals for recent version metrics", %{conn: conn} do
      prompt = prompt_fixture()
      provider = provider_fixture()
      {:ok, version} = Prompts.create_prompt_version(prompt, "Test {{var}}")
      suite = suite_fixture(%{prompt_id: prompt.id})

      for {passed, failed} <- [{5, 0}, {0, 5}] do
        {:ok, _suite_run} =
          Aludel.Evals.create_suite_run(%{
            suite_id: suite.id,
            prompt_version_id: version.id,
            provider_id: provider.id,
            passed: passed,
            failed: failed,
            avg_cost_usd: Decimal.new("0.01"),
            avg_latency_ms: 200
          })
      end

      {:ok, view, _html} = live(conn, "/prompts/#{prompt.id}/evolution")

      assert has_element?(view, "#evolution-window", "Last 30 days")
      assert has_element?(view, "#evolution-stability-1", "Volatile")
      assert has_element?(view, "#evolution-cost-per-pass-1", "$0.0200")
      assert has_element?(view, "#evolution-latency-per-pass-1", "400ms")
    end

    test "renders explicit zero-pass efficiency state", %{conn: conn} do
      prompt = prompt_fixture()
      provider = provider_fixture()
      {:ok, version} = Prompts.create_prompt_version(prompt, "Test {{var}}")
      suite = suite_fixture(%{prompt_id: prompt.id})

      {:ok, _suite_run} =
        Aludel.Evals.create_suite_run(%{
          suite_id: suite.id,
          prompt_version_id: version.id,
          provider_id: provider.id,
          passed: 0,
          failed: 5,
          avg_cost_usd: Decimal.new("0.01"),
          avg_latency_ms: 200
        })

      {:ok, view, _html} = live(conn, "/prompts/#{prompt.id}/evolution")

      assert has_element?(
               view,
               "#evolution-cost-per-pass-1[data-state='no-passes']",
               "No passing tests"
             )
    end

    test "renders a suite-scoped Pareto frontier with trade-offs", %{conn: conn} do
      prompt = prompt_fixture()
      provider = provider_fixture()
      {:ok, v1} = Prompts.create_prompt_version(prompt, "Version 1")
      {:ok, v2} = Prompts.create_prompt_version(prompt, "Version 2")
      suite = suite_fixture(%{prompt_id: prompt.id, name: "Regression Suite"})

      for {version, passed, failed, cost, latency} <- [
            {v1, 8, 2, "0.02", 300},
            {v2, 9, 1, "0.01", 250}
          ] do
        {:ok, _suite_run} =
          Aludel.Evals.create_suite_run(%{
            suite_id: suite.id,
            prompt_version_id: version.id,
            provider_id: provider.id,
            passed: passed,
            failed: failed,
            avg_cost_usd: Decimal.new(cost),
            avg_latency_ms: latency
          })
      end

      {:ok, view, _html} = live(conn, "/prompts/#{prompt.id}/evolution")

      assert has_element?(view, "#pareto-suite", "Regression Suite")
      assert has_element?(view, "#pareto-frontier")
      assert has_element?(view, "#pareto-version-2[data-pareto-status='frontier']")
      assert has_element?(view, "#pareto-version-1[data-pareto-status='dominated']")
    end
  end

  describe "edge cases" do
    test "handles prompt with no suite runs", %{conn: conn} do
      prompt = prompt_fixture()
      {:ok, _version} = Prompts.create_prompt_version(prompt, "Test {{var}}")

      {:ok, view, _html} = live(conn, "/prompts/#{prompt.id}/evolution")

      state = :sys.get_state(view.pid)
      socket = state.socket

      [metric] = socket.assigns.metrics
      assert metric.total_runs == 0
      assert metric.avg_pass_rate == nil
      assert metric.avg_cost_usd == nil
      assert metric.avg_latency_ms == nil
    end

    test "handles multiple versions with mixed data", %{conn: conn} do
      prompt = prompt_fixture()
      provider = provider_fixture()
      {:ok, v1} = Prompts.create_prompt_version(prompt, "Version 1 {{var}}")
      {:ok, _v2} = Prompts.create_prompt_version(prompt, "Version 2 {{var}}")
      suite = suite_fixture(%{prompt_id: prompt.id})

      # Only v1 has suite runs
      {:ok, _sr} =
        Aludel.Evals.create_suite_run(%{
          suite_id: suite.id,
          prompt_version_id: v1.id,
          provider_id: provider.id,
          passed: 7,
          failed: 3
        })

      {:ok, view, _html} = live(conn, "/prompts/#{prompt.id}/evolution")

      state = :sys.get_state(view.pid)
      socket = state.socket

      assert length(socket.assigns.metrics) == 2

      # v2 (newest, at index 0) has no runs
      v2_metric = Enum.at(socket.assigns.metrics, 0)
      assert v2_metric.total_runs == 0

      # v1 (at index 1) has runs
      v1_metric = Enum.at(socket.assigns.metrics, 1)
      assert v1_metric.total_runs == 1
      assert v1_metric.avg_pass_rate == 70.0
    end
  end
end
