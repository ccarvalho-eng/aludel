defmodule Aludel.Web.PromptLive.Show do
  @moduledoc """
  LiveView for displaying a prompt and all its versions.
  """

  use Aludel.Web, :live_view

  alias Aludel.Prompts

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_params(%{"id" => id}, _uri, socket) do
    prompt = Prompts.get_prompt_with_versions!(id)
    latest_version = List.first(prompt.versions)

    {:noreply,
     socket
     |> assign(:page_title, prompt.name)
     |> assign(:prompt, prompt)
     |> select_version(prompt, latest_version && latest_version.id)}
  end

  @impl Phoenix.LiveView
  def handle_event("select_version", %{"version-id" => version_id}, socket) do
    {:noreply, select_version(socket, socket.assigns.prompt, version_id)}
  end

  def handle_event(
        "select_comparison_version",
        %{"comparison" => %{"version_id" => comparison_version_id}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:comparison_version_id, comparison_version_id)
     |> assign(
       :version_comparison,
       version_comparison(
         socket.assigns.prompt.versions,
         socket.assigns.selected_version_id,
         comparison_version_id
       )
     )
     |> assign(:show_version_diff, false)}
  end

  def handle_event("show_version_diff", _params, socket) do
    if socket.assigns.version_comparison do
      {:noreply, assign(socket, :show_version_diff, true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("hide_version_diff", _params, socket) do
    {:noreply, assign(socket, :show_version_diff, false)}
  end

  defp select_version(socket, prompt, version_id) do
    comparison_version_id = default_comparison_version_id(prompt.versions, version_id)

    socket
    |> assign(:selected_version_id, version_id)
    |> assign(:comparison_version_id, comparison_version_id)
    |> assign(
      :version_comparison,
      version_comparison(prompt.versions, version_id, comparison_version_id)
    )
    |> assign(:show_version_diff, false)
  end

  defp version_comparison(versions, selected_version_id, comparison_version_id) do
    current_version = Enum.find(versions, &(&1.id == selected_version_id))
    comparison_version = Enum.find(versions, &(&1.id == comparison_version_id))
    build_version_comparison(comparison_version, current_version)
  end

  defp default_comparison_version_id(versions, selected_version_id) do
    selected_index = Enum.find_index(versions, &(&1.id == selected_version_id))
    adjacent_older = selected_index && Enum.at(versions, selected_index + 1)
    fallback = Enum.find(versions, &(&1.id != selected_version_id))
    (adjacent_older || fallback) && (adjacent_older || fallback).id
  end

  defp build_version_comparison(nil, _current_version) do
    nil
  end

  defp build_version_comparison(_comparison_version, nil) do
    nil
  end

  defp build_version_comparison(comparison_version, current_version) do
    %{
      current_version: current_version,
      previous_version: comparison_version,
      template_diff:
        List.myers_difference(
          String.split(comparison_version.template, "\n"),
          String.split(current_version.template, "\n")
        ),
      added_variables: current_version.variables -- comparison_version.variables,
      removed_variables: comparison_version.variables -- current_version.variables
    }
  end
end
