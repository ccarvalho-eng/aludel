defmodule Aludel.Web.SuiteLive.Report do
  @moduledoc """
  LiveView for previewing and downloading a persisted suite run report.
  """

  use Aludel.Web, :live_view

  alias Aludel.Evals
  alias Aludel.Evals.Reporter

  @formats ~w(console json junit github)
  @max_preview_characters 100_000

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_params(%{"id" => id}, _uri, socket) do
    suite_run = Evals.get_suite_run_for_export!(id)

    {:noreply,
     socket
     |> assign(:page_title, "Evaluation report")
     |> assign(:suite_run, suite_run)
     |> assign_report("console", false)}
  end

  @impl Phoenix.LiveView
  def handle_event("preview", %{"report" => params}, socket) do
    format = normalize_format(Map.get(params, "format"))
    include_output = include_output?(Map.get(params, "include_output"))

    {:noreply, assign_report(socket, format, include_output)}
  end

  defp assign_report(socket, format, include_output) do
    options = report_options(format, include_output)

    case Reporter.render(socket.assigns.suite_run, format_atom(format), options) do
      {:ok, rendered} ->
        {preview, truncated?} = bounded_preview(rendered)

        socket
        |> assign(:report_form, report_form(format, include_output))
        |> assign(:format, format)
        |> assign(:include_output, include_output)
        |> assign(:preview, preview)
        |> assign(:preview_truncated, truncated?)
        |> assign(:render_error, nil)

      {:error, _reason} ->
        socket
        |> assign(:report_form, report_form(format, include_output))
        |> assign(:format, format)
        |> assign(:include_output, include_output)
        |> assign(:preview, "")
        |> assign(:preview_truncated, false)
        |> assign(:render_error, "This report could not be rendered")
    end
  end

  defp normalize_format(format) when format in @formats do
    format
  end

  defp normalize_format(_format) do
    "console"
  end

  defp format_atom("console") do
    :console
  end

  defp format_atom("json") do
    :json
  end

  defp format_atom("junit") do
    :junit
  end

  defp format_atom("github") do
    :github
  end

  defp report_options("json", _include_output) do
    [pretty: true]
  end

  defp report_options("junit", include_output) do
    [include_output: include_output]
  end

  defp report_options(_format, _include_output) do
    []
  end

  defp include_output?(value) do
    value in [true, "true", "1", "on"]
  end

  defp report_form(format, include_output) do
    to_form(
      %{"format" => format, "include_output" => include_output},
      as: :report
    )
  end

  defp bounded_preview(rendered) do
    if String.length(rendered) > @max_preview_characters do
      {String.slice(rendered, 0, @max_preview_characters), true}
    else
      {rendered, false}
    end
  end

  defp format_options do
    [
      {"Console text", "console"},
      {"JSON v2", "json"},
      {"JUnit XML", "junit"},
      {"GitHub annotations", "github"}
    ]
  end

  defp format_label("console") do
    "console report"
  end

  defp format_label("json") do
    "JSON report"
  end

  defp format_label("junit") do
    "JUnit XML"
  end

  defp format_label("github") do
    "GitHub annotations"
  end

  defp download_params("junit", true) do
    %{"include_output" => "true"}
  end

  defp download_params(_format, _include_output) do
    %{}
  end
end
