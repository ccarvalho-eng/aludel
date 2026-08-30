defmodule Aludel.Web.PromptLive.Evolution do
  @moduledoc """
  LiveView for displaying prompt evolution metrics and performance
  trends with interactive charting.
  """

  use Aludel.Web, :live_view

  alias Aludel.Evals
  alias Aludel.Prompts
  alias Aludel.Prompts.{Evolution, Optimization}

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       view_mode: :overall,
       show_breakdown_sidebar: false,
       show_export_dropdown: false
     )}
  end

  @impl Phoenix.LiveView
  def handle_params(%{"id" => id} = params, _uri, socket) do
    prompt = Prompts.get_prompt!(id)
    suites = Evals.list_suites_for_prompt(id)
    selected_suite = select_suite(suites, params["suite_id"])
    metric_options = metric_options(selected_suite)
    metrics = Prompts.get_evolution_metrics(id, metric_options)
    chart_data = Evolution.prepare_chart_data(metrics)
    pareto_analysis = Optimization.analyze(metrics)

    # Reverse metrics for table display (descending order: newest first)
    reversed_metrics = Enum.reverse(metrics)

    {:noreply,
     socket
     |> assign(:page_title, "#{prompt.name} - Evolution")
     |> assign(:prompt, prompt)
     |> assign(:analysis_window, 30)
     |> assign(:suites, suites)
     |> assign(:selected_suite, selected_suite)
     |> assign(:pareto_analysis, pareto_analysis)
     |> assign(:metrics, reversed_metrics)
     |> assign(:chart_data, chart_data)}
  end

  @impl Phoenix.LiveView
  def handle_event("toggle_view_mode", _params, socket) do
    new_mode =
      case socket.assigns.view_mode do
        :overall -> :by_provider
        :by_provider -> :overall
      end

    {:noreply,
     socket
     |> assign(view_mode: new_mode)
     |> push_event("update-chart", %{
       chart_data: socket.assigns.chart_data,
       view_mode: new_mode
     })}
  end

  @impl Phoenix.LiveView
  def handle_event("chart-mounted", _params, socket) do
    {:noreply,
     push_event(socket, "update-chart", %{
       chart_data: socket.assigns.chart_data,
       view_mode: socket.assigns.view_mode
     })}
  end

  def handle_event("toggle_breakdown_sidebar", _params, socket) do
    {:noreply, assign(socket, :show_breakdown_sidebar, !socket.assigns.show_breakdown_sidebar)}
  end

  def handle_event("toggle_export_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_export_dropdown, !socket.assigns.show_export_dropdown)}
  end

  def handle_event("close_export_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_export_dropdown, false)}
  end

  def handle_event("select_pareto_suite", %{"suite_id" => suite_id}, socket) do
    {:noreply,
     push_patch(socket,
       to: aludel_path("prompts/#{socket.assigns.prompt.id}/evolution?suite_id=#{suite_id}")
     )}
  end

  defp efficiency_state(%{efficiency_status: :no_passes}) do
    "no-passes"
  end

  defp efficiency_state(%{efficiency_status: :no_tests}) do
    "no-tests"
  end

  defp efficiency_state(_metric) do
    "available"
  end

  defp format_cost_per_pass(%{efficiency_status: :no_passes}) do
    "No passing tests"
  end

  defp format_cost_per_pass(%{cost_per_passed_test: nil}) do
    "Unavailable"
  end

  defp format_cost_per_pass(metric) do
    "$#{:erlang.float_to_binary(metric.cost_per_passed_test, decimals: 4)}"
  end

  defp format_latency_per_pass(%{efficiency_status: :no_passes}) do
    "No passing tests"
  end

  defp format_latency_per_pass(%{latency_per_passed_test: nil}) do
    "Unavailable"
  end

  defp format_latency_per_pass(metric) do
    "#{round(metric.latency_per_passed_test)}ms"
  end

  defp stability_label(:insufficient_data) do
    "Needs more runs"
  end

  defp stability_label(stability) do
    stability
    |> Atom.to_string()
    |> String.capitalize()
  end

  defp select_suite([], _suite_id) do
    nil
  end

  defp select_suite(suites, suite_id) do
    Enum.find(suites, &(&1.id == suite_id)) || List.first(suites)
  end

  defp metric_options(nil) do
    [days: 30]
  end

  defp metric_options(suite) do
    [days: 30, suite_id: suite.id]
  end
end
