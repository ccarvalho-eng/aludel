defmodule Aludel.Web.DatasetLive.RedTeamCatalog do
  @moduledoc """
  LiveView for browsing and materializing curated red-team cases.
  """

  use Aludel.Web, :live_view

  alias Aludel.Datasets
  alias Aludel.Providers
  alias Aludel.RedTeam

  @default_params %{
    "variable" => "input",
    "judge_provider_id" => "",
    "judge_threshold" => "80"
  }

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_params(%{"id" => id}, _uri, socket) do
    dataset = Datasets.get_dataset!(id)
    cases = RedTeam.all()
    params = Map.put(@default_params, "case_ids", Enum.map(cases, & &1.id))

    {:noreply,
     socket
     |> assign(:page_title, "Curated red-team cases")
     |> assign(:dataset, dataset)
     |> assign(:cases, cases)
     |> assign(:providers, Providers.list_providers())
     |> assign(:materialization_errors, [])
     |> assign(:materialization_result, nil)
     |> assign_materialization(params)}
  end

  @impl Phoenix.LiveView
  def handle_event("validate_materialization", %{"materialization" => params}, socket) do
    {:noreply,
     socket
     |> assign_materialization(params)
     |> assign(:materialization_errors, [])
     |> assign(:materialization_result, nil)}
  end

  @impl Phoenix.LiveView
  def handle_event("materialize", %{"materialization" => params}, socket) do
    case materialization_options(params, socket.assigns.cases, socket.assigns.providers) do
      {:ok, options} ->
        materialize(socket, params, options)

      {:error, message} ->
        {:noreply,
         socket
         |> assign_materialization(params)
         |> assign(:materialization_errors, [message])
         |> assign(:materialization_result, nil)}
    end
  end

  defp materialize(socket, params, options) do
    case RedTeam.materialize(socket.assigns.dataset, options) do
      {:ok, result} ->
        created_count = length(result.created)
        skipped_count = length(result.skipped)

        {:noreply,
         socket
         |> assign_materialization(params)
         |> assign(:materialization_errors, [])
         |> assign(:materialization_result, %{
           created: created_count,
           skipped: skipped_count
         })
         |> put_flash(:info, materialization_message(created_count, skipped_count))}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign_materialization(params)
         |> assign(:materialization_errors, [materialization_error(reason)])
         |> assign(:materialization_result, nil)}
    end
  end

  defp materialization_options(params, cases, providers) do
    with {:ok, case_ids} <- selected_case_ids(params, cases),
         {:ok, provider_id} <- judge_provider_id(params, providers),
         {:ok, threshold} <- judge_threshold(params) do
      {:ok,
       [
         case_ids: case_ids,
         variable: Map.get(params, "variable", ""),
         judge_provider_id: provider_id,
         judge_threshold: threshold
       ]}
    end
  end

  defp selected_case_ids(params, cases) do
    case_ids = params |> Map.get("case_ids", []) |> List.wrap()
    known_ids = MapSet.new(cases, & &1.id)

    cond do
      case_ids == [] ->
        {:error, "Select at least one case"}

      Enum.any?(case_ids, &(not MapSet.member?(known_ids, &1))) ->
        {:error, "Unknown catalog case"}

      true ->
        {:ok, Enum.uniq(case_ids)}
    end
  end

  defp judge_provider_id(params, providers) do
    provider_id = Map.get(params, "judge_provider_id", "")

    cond do
      provider_id == "" ->
        {:ok, nil}

      Enum.any?(providers, &(&1.id == provider_id)) ->
        {:ok, provider_id}

      true ->
        {:error, "Choose a configured judge provider"}
    end
  end

  defp judge_threshold(params) do
    case Float.parse(Map.get(params, "judge_threshold", "")) do
      {threshold, ""} when threshold >= 0 and threshold <= 100 ->
        {:ok, threshold}

      _invalid ->
        {:error, "Judge threshold must be a number between 0 and 100"}
    end
  end

  defp assign_materialization(socket, params) do
    selected_case_ids = params |> Map.get("case_ids", []) |> List.wrap()

    socket
    |> assign(:selected_case_ids, selected_case_ids)
    |> assign(:materialization_form, to_form(params, as: :materialization))
  end

  defp materialization_error(:invalid_variable) do
    "Variable must start with a letter or underscore and use only letters, numbers, dots, dashes, or underscores"
  end

  defp materialization_error(:invalid_judge_provider_id) do
    "Choose a configured judge provider"
  end

  defp materialization_error(:invalid_judge_threshold) do
    "Judge threshold must be a number between 0 and 100"
  end

  defp materialization_error({:deduplication_conflict, _key}) do
    "An existing entry conflicts with the selected catalog case"
  end

  defp materialization_error(:dataset_not_found) do
    "Dataset no longer exists"
  end

  defp materialization_error(_reason) do
    "Cases could not be materialized"
  end

  defp materialization_message(created, 0) do
    "#{created} #{case_label(created)} created"
  end

  defp materialization_message(0, skipped) do
    "#{skipped} #{case_label(skipped)} already present"
  end

  defp materialization_message(created, skipped) do
    "#{created} #{case_label(created)} created; #{skipped} already present"
  end

  defp case_label(1) do
    "case"
  end

  defp case_label(_count) do
    "cases"
  end

  defp category_label(category) do
    category
    |> Atom.to_string()
    |> String.replace("_", " ")
  end
end
