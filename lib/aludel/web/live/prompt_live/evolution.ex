defmodule Aludel.Web.PromptLive.Evolution do
  @moduledoc """
  LiveView for displaying prompt evolution metrics and performance
  trends with interactive charting.
  """

  use Aludel.Web, :live_view

  alias Aludel.Evals
  alias Aludel.Prompts
  alias Aludel.Prompts.{Evolution, Optimization}
  alias Aludel.Providers

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       view_mode: :overall,
       show_breakdown_sidebar: false,
       show_export_dropdown: false,
       generating_suggestion: false
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
    providers = Providers.list_providers()
    suggestions = Optimization.list_suggestions(id)

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
     |> assign(:providers, providers)
     |> assign(:suggestions, suggestions)
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

  def handle_event(
        "generate_prompt_suggestion",
        %{
          "suggestion" => %{
            "source_version_id" => source_version_id,
            "provider_id" => provider_id
          }
        },
        %{assigns: %{generating_suggestion: false}} = socket
      ) do
    case socket.assigns.selected_suite do
      nil ->
        {:noreply, put_flash(socket, :error, "Create an evaluation suite first.")}

      suite ->
        socket =
          start_async(socket, :generate_suggestion, fn ->
            Optimization.generate_suggestion(source_version_id, suite.id, provider_id)
          end)

        {:noreply, assign(socket, :generating_suggestion, true)}
    end
  end

  def handle_event("generate_prompt_suggestion", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("accept_prompt_suggestion", %{"id" => suggestion_id}, socket) do
    case Optimization.accept_suggestion(suggestion_id, socket.assigns.prompt.id) do
      {:ok, _suggestion} ->
        {:noreply,
         socket
         |> put_flash(:info, "Suggestion accepted as a new prompt version.")
         |> push_patch(to: current_evolution_path(socket))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, suggestion_error(reason))}
    end
  end

  def handle_event("dismiss_prompt_suggestion", %{"id" => suggestion_id}, socket) do
    case Optimization.dismiss_suggestion(suggestion_id, socket.assigns.prompt.id) do
      {:ok, _suggestion} ->
        {:noreply,
         socket
         |> assign(:suggestions, Optimization.list_suggestions(socket.assigns.prompt.id))
         |> put_flash(:info, "Suggestion dismissed.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, suggestion_error(reason))}
    end
  end

  @impl Phoenix.LiveView
  def handle_async(:generate_suggestion, {:ok, {:ok, _suggestion}}, socket) do
    {:noreply,
     socket
     |> assign(:generating_suggestion, false)
     |> assign(:suggestions, Optimization.list_suggestions(socket.assigns.prompt.id))
     |> put_flash(:info, "Prompt suggestion generated for review.")}
  end

  def handle_async(:generate_suggestion, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:generating_suggestion, false)
     |> put_flash(:error, suggestion_error(reason))}
  end

  def handle_async(:generate_suggestion, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:generating_suggestion, false)
     |> put_flash(:error, "The prompt suggestion could not be completed.")}
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

  defp current_evolution_path(socket) do
    base_path = "prompts/#{socket.assigns.prompt.id}/evolution"

    case socket.assigns.selected_suite do
      nil -> aludel_path(base_path)
      suite -> aludel_path("#{base_path}?suite_id=#{suite.id}")
    end
  end

  defp suggestion_error(:no_failures) do
    "No failed evaluations are available for reflection."
  end

  defp suggestion_error(:already_resolved) do
    "This suggestion has already been reviewed."
  end

  defp suggestion_error(:pending_suggestion_exists) do
    "A pending suggestion already exists for this version, suite, and provider."
  end

  defp suggestion_error({:missing_variables, variables}) do
    "The suggestion omitted required variables: #{Enum.join(variables, ", ")}"
  end

  defp suggestion_error(%Ecto.Changeset{}) do
    "A pending suggestion already exists for this version, suite, and provider."
  end

  defp suggestion_error(_reason) do
    "The prompt suggestion could not be completed."
  end
end
