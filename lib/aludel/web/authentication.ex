defmodule Aludel.Web.Authentication do
  @moduledoc """
  Loads dashboard session context and enforces LiveView access decisions.
  """

  import Phoenix.Component, only: [assign: 3]

  @read_only_events %{
    Aludel.Web.DashboardLive => MapSet.new(~w(
        toggle_cost_breakdown
        toggle_latency_breakdown
        toggle_activity_chart
        toggle_cost_view
        toggle_pass_rates
      )),
    Aludel.Web.DatasetLive.GeneratedRedTeam =>
      MapSet.new(~w(validate_generation validate_import)),
    Aludel.Web.DatasetLive.Index => MapSet.new(~w(validate)),
    Aludel.Web.DatasetLive.RedTeamCatalog => MapSet.new(~w(validate_materialization)),
    Aludel.Web.DatasetLive.Show => MapSet.new(~w(validate_dataset validate_entry filter_entries)),
    Aludel.Web.PromptLive.Evolution => MapSet.new(~w(
        toggle_view_mode
        chart-mounted
        toggle_breakdown_sidebar
        toggle_export_dropdown
        close_export_dropdown
        select_pareto_suite
      )),
    Aludel.Web.PromptLive.Index => MapSet.new(~w(
        search
        toggle_tag
        clear_filters
        toggle_project
        select_project
        clear_project
        validate_create_project
        validate_update_project
        phx-noop
      )),
    Aludel.Web.PromptLive.New => MapSet.new(~w(validate)),
    Aludel.Web.PromptLive.Show => MapSet.new(~w(
        select_version
        select_comparison_version
        show_version_diff
        hide_version_diff
      )),
    Aludel.Web.ProviderLive.New => MapSet.new(~w(validate)),
    Aludel.Web.RunLive.New => MapSet.new(~w(validate)),
    Aludel.Web.SuiteLive.Index => MapSet.new(~w(
        toggle_project
        validate_create_project
        validate_update_project
        phx-noop
      )),
    Aludel.Web.SuiteLive.New => MapSet.new(~w(
        validate
        add_test_case
        remove_test_case
        toggle_assertion_mode
        add_assertion
        remove_assertion
      )),
    Aludel.Web.SuiteLive.Policy => MapSet.new(~w(validate)),
    Aludel.Web.SuiteLive.Report => MapSet.new(~w(preview)),
    Aludel.Web.SuiteLive.Show => MapSet.new(~w(
        edit_suite_metadata
        cancel_edit_suite_metadata
        validate_suite_metadata
        select_version
        select_provider
        validate_run_suite
        toggle_assertion_mode
        add_assertion
        remove_assertion
        toggle_test_case_import
        validate_test_case_import
        cancel_test_case_import_upload
        preview_test_case_import
        edit_test_case
        cancel_edit
        validate_test_case
      ))
  }

  @read_only_message "This dashboard is read-only. Changes and model requests are disabled."

  @doc false
  def on_mount(:default, _params, session, socket) do
    # Store routing info in process dictionary for aludel_path helper
    Process.put(:routing, {socket, session["prefix"]})

    socket =
      socket
      |> assign(:access, session["access"])
      |> assign(:refresh, session["refresh"])
      |> assign(:user, session["user"])
      |> assign(:resolver, session["resolver"])
      |> assign(:aludel_name, session["aludel_name"])
      |> assign(:prefix, session["prefix"])
      |> assign(:logo_path, session["logo_path"])
      |> assign(:csp_nonces, session["csp_nonces"])
      |> assign(:live_path, session["live_path"])
      |> assign(:live_transport, session["live_transport"])
      |> attach_access_hook()

    {:cont, socket}
  end

  @doc false
  @spec authorize_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def authorize_event(_event, _params, %{assigns: %{access: :all}} = socket) do
    {:cont, socket}
  end

  def authorize_event(event, _params, %{assigns: %{access: :read_only}, view: view} = socket) do
    allowed_events = Map.get(@read_only_events, view, MapSet.new())

    if MapSet.member?(allowed_events, event) do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.put_flash(socket, :error, @read_only_message)}
    end
  end

  def authorize_event(_event, _params, socket) do
    {:halt, Phoenix.LiveView.put_flash(socket, :error, @read_only_message)}
  end

  defp attach_access_hook(socket) do
    if Phoenix.LiveView.connected?(socket) do
      Phoenix.LiveView.attach_hook(
        socket,
        :aludel_authorize_access,
        :handle_event,
        &authorize_event/3
      )
    else
      socket
    end
  end
end
