defmodule Aludel.Web.DashboardLive do
  @moduledoc """
  LiveView for displaying the dashboard with recent runs, cost
  aggregation, and pass rate statistics.
  """

  use Aludel.Web, :live_view

  alias Aludel.Evals
  alias Aludel.Runs
  alias Aludel.Stats.Activity
  alias Aludel.Stats.Costs
  alias Aludel.Stats.Latency
  alias Aludel.Stats.Overview

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:show_cost_breakdown, false)
      |> assign(:cost_view, :provider)
      |> assign(:show_latency_breakdown, false)
      |> assign(:show_activity_chart, true)
      |> assign(:show_pass_rates, false)

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_params(_params, _uri, socket) do
    recent_activity = Activity.list_recent_activity(10)
    pass_rates = Evals.pass_rates_by_prompt() |> sort_by_pass_rate()

    # Calculate key metrics
    total_runs = Overview.total_runs()
    {total_passed, total_failed} = Overview.test_totals()
    success_rate = Overview.success_rate(total_passed, total_failed)
    avg_latency = Overview.avg_latency()
    latency_percentiles = Latency.latency_percentiles()
    total_cost = Runs.total_cost()
    # Calculate cost_per_run here to avoid redundant DB queries
    cost_per_run = if total_runs > 0, do: total_cost / total_runs, else: 0.0
    rolling_windows = Overview.rolling_comparisons()
    trends = Map.fetch!(rolling_windows, 7)

    # Breakdown stats
    cost_by_provider = Costs.cost_by_provider()
    cost_by_prompt = Costs.cost_by_prompt()
    latency_by_provider = Latency.latency_by_provider()
    daily_activity = Activity.daily_activity(30)

    # Get last run time
    last_run_at = if recent_activity != [], do: List.first(recent_activity).inserted_at, else: nil

    socket =
      socket
      |> assign(:page_title, "Dashboard")
      |> assign(:recent_activity, recent_activity)
      |> assign(:pass_rates, pass_rates)
      |> assign(:total_runs, total_runs)
      |> assign(:total_passed, total_passed)
      |> assign(:total_failed, total_failed)
      |> assign(:success_rate, success_rate)
      |> assign(:avg_latency, avg_latency)
      |> assign(:latency_p50, latency_percentiles.p50)
      |> assign(:latency_p95, latency_percentiles.p95)
      |> assign(:total_cost, total_cost)
      |> assign(:cost_per_run, cost_per_run)
      |> assign(:trends, trends)
      |> assign(:rolling_windows, rolling_windows)
      |> assign(:cost_by_provider, cost_by_provider)
      |> assign(:cost_by_prompt, cost_by_prompt)
      |> assign(:latency_by_provider, latency_by_provider)
      |> assign(:daily_activity, daily_activity)
      |> assign(:last_run_at, last_run_at)

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("toggle_cost_breakdown", _params, socket) do
    new_value = !socket.assigns.show_cost_breakdown

    socket =
      socket
      |> assign(:show_cost_breakdown, new_value)
      |> assign(:show_latency_breakdown, false)
      |> assign(:show_activity_chart, false)
      |> assign(:show_pass_rates, false)

    {:noreply, socket}
  end

  def handle_event("toggle_latency_breakdown", _params, socket) do
    new_value = !socket.assigns.show_latency_breakdown

    socket =
      socket
      |> assign(:show_cost_breakdown, false)
      |> assign(:show_latency_breakdown, new_value)
      |> assign(:show_activity_chart, false)
      |> assign(:show_pass_rates, false)

    {:noreply, socket}
  end

  def handle_event("toggle_activity_chart", _params, socket) do
    new_value = !socket.assigns.show_activity_chart

    socket =
      socket
      |> assign(:show_cost_breakdown, false)
      |> assign(:show_latency_breakdown, false)
      |> assign(:show_activity_chart, new_value)
      |> assign(:show_pass_rates, false)

    {:noreply, socket}
  end

  def handle_event("toggle_cost_view", _params, socket) do
    new_view = if socket.assigns.cost_view == :provider, do: :prompt, else: :provider
    {:noreply, assign(socket, :cost_view, new_view)}
  end

  def handle_event("toggle_pass_rates", _params, socket) do
    new_value = !socket.assigns.show_pass_rates

    socket =
      socket
      |> assign(:show_cost_breakdown, false)
      |> assign(:show_latency_breakdown, false)
      |> assign(:show_activity_chart, false)
      |> assign(:show_pass_rates, new_value)

    {:noreply, socket}
  end

  defp sort_by_pass_rate(pass_rates) do
    Enum.sort_by(pass_rates, fn rate ->
      total = (rate.total_passed || 0) + (rate.total_failed || 0)

      if total > 0 do
        -(rate.total_passed || 0) / total
      else
        0
      end
    end)
  end

  defp efficiency_state(%{efficiency_status: :no_passes}) do
    "no-passes"
  end

  defp efficiency_state(%{efficiency_status: :no_tests}) do
    "no-tests"
  end

  defp efficiency_state(_stats) do
    "available"
  end

  defp format_pass_rate(nil) do
    "No tests"
  end

  defp format_pass_rate(value) do
    "#{:erlang.float_to_binary(value * 1.0, decimals: 1)}%"
  end

  defp format_cost_per_pass(%{efficiency_status: :no_passes}) do
    "No passing tests"
  end

  defp format_cost_per_pass(%{cost_per_passed_test: nil}) do
    "Unavailable"
  end

  defp format_cost_per_pass(stats) do
    "$#{:erlang.float_to_binary(stats.cost_per_passed_test, decimals: 4)}"
  end

  defp format_latency_per_pass(%{efficiency_status: :no_passes}) do
    "No passing tests"
  end

  defp format_latency_per_pass(%{latency_per_passed_test: nil}) do
    "Unavailable"
  end

  defp format_latency_per_pass(stats) do
    "#{round(stats.latency_per_passed_test)}ms"
  end

  defp stability_label(:insufficient_data) do
    "Needs more runs"
  end

  defp stability_label(stability) do
    stability
    |> Atom.to_string()
    |> String.capitalize()
  end
end
