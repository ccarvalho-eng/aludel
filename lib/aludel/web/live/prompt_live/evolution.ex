defmodule Aludel.Web.PromptLive.Evolution do
  @moduledoc """
  LiveView for displaying prompt evolution metrics and performance
  trends with interactive charting.
  """

  use Aludel.Web, :live_view

  alias Aludel.Prompts
  alias Aludel.Prompts.Evolution

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
  def handle_params(%{"id" => id}, _uri, socket) do
    prompt = Prompts.get_prompt!(id)
    metrics = Prompts.get_evolution_metrics(id)
    chart_data = Evolution.prepare_chart_data(metrics)

    # Reverse metrics for table display (descending order: newest first)
    reversed_metrics = Enum.reverse(metrics)

    {:noreply,
     socket
     |> assign(:page_title, "#{prompt.name} - Evolution")
     |> assign(:prompt, prompt)
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
end
