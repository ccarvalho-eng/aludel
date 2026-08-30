defmodule Aludel.Web.DatasetLive.Show do
  @moduledoc """
  Edits a dataset and its ordered evaluation entries.
  """

  use Aludel.Web, :live_view

  alias Aludel.Web.CoreComponents

  alias Aludel.Datasets
  alias Aludel.Datasets.Params

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, stream_configure(socket, :entries, dom_id: &"dataset-entry-#{&1.id}")}
  end

  @impl Phoenix.LiveView
  def handle_params(%{"id" => id}, _uri, socket) do
    dataset = Datasets.get_dataset!(id)

    {:noreply,
     socket
     |> assign(:page_title, dataset.name)
     |> assign(:dataset, dataset)
     |> assign(:dataset_form, dataset_form(Params.dataset_defaults(dataset)))
     |> assign(:entry_form, entry_form(Params.entry_defaults()))
     |> assign(:filter_metadata, %{})
     |> assign(:filter_form, filter_form(%{"metadata_json" => "{}"}))
     |> refresh_entries()}
  end

  @impl Phoenix.LiveView
  def handle_event("validate_dataset", %{"dataset" => params}, socket) do
    form =
      case Params.parse_dataset(params) do
        {:ok, _attrs} -> dataset_form(params)
        {:error, errors} -> dataset_form(params, errors)
      end

    {:noreply, assign(socket, :dataset_form, form)}
  end

  @impl Phoenix.LiveView
  def handle_event("update_dataset", %{"dataset" => params}, socket) do
    with {:ok, attrs} <- Params.parse_dataset(params),
         {:ok, dataset} <- Datasets.update_dataset(socket.assigns.dataset, attrs) do
      {:noreply,
       socket
       |> assign(:dataset, dataset)
       |> assign(:page_title, dataset.name)
       |> assign(:dataset_form, dataset_form(Params.dataset_defaults(dataset)))
       |> put_flash(:info, "Dataset updated")}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket, :dataset_form, dataset_form(params, map_dataset_errors(changeset.errors)))}

      {:error, errors} ->
        {:noreply, assign(socket, :dataset_form, dataset_form(params, errors))}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("validate_entry", %{"entry" => params}, socket) do
    form =
      case Params.parse_entry(params) do
        {:ok, _attrs} -> entry_form(params)
        {:error, errors} -> entry_form(params, errors)
      end

    {:noreply, assign(socket, :entry_form, form)}
  end

  @impl Phoenix.LiveView
  def handle_event("create_entry", %{"entry" => params}, socket) do
    with {:ok, attrs} <- Params.parse_entry(params),
         {:ok, _entry} <- Datasets.create_entry(socket.assigns.dataset, attrs) do
      {:noreply,
       socket
       |> assign(:entry_form, entry_form(Params.entry_defaults()))
       |> refresh_entries()
       |> put_flash(:info, "Dataset entry created")}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket, :entry_form, entry_form(params, map_entry_errors(changeset.errors)))}

      {:error, errors} ->
        {:noreply, assign(socket, :entry_form, entry_form(params, errors))}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("delete_entry", %{"id" => id}, socket) do
    case Datasets.get_entry(socket.assigns.dataset, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Dataset entry not found")}

      entry ->
        case Datasets.delete_entry(entry) do
          {:ok, _deleted} ->
            {:noreply,
             socket
             |> refresh_entries()
             |> put_flash(:info, "Dataset entry deleted")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Dataset entry could not be deleted")}
        end
    end
  end

  @impl Phoenix.LiveView
  def handle_event("filter_entries", %{"filter" => params}, socket) do
    case Params.parse_metadata_filter(params) do
      {:ok, metadata} ->
        {:noreply,
         socket
         |> assign(:filter_metadata, metadata)
         |> assign(:filter_form, filter_form(params))
         |> refresh_entries()}

      {:error, error} ->
        {:noreply, assign(socket, :filter_form, filter_form(params, [error]))}
    end
  end

  defp refresh_entries(socket) do
    entries =
      Datasets.list_entries(socket.assigns.dataset, metadata: socket.assigns.filter_metadata)

    socket
    |> assign(:entries_empty?, entries == [])
    |> assign(:entry_count, length(entries))
    |> stream(:entries, entries, reset: true)
  end

  defp dataset_form(params, errors \\ []) do
    to_form(params, as: :dataset, errors: errors)
  end

  defp entry_form(params, errors \\ []) do
    to_form(params, as: :entry, errors: errors)
  end

  defp filter_form(params, errors \\ []) do
    to_form(params, as: :filter, errors: errors)
  end

  defp map_dataset_errors(errors) do
    Enum.map(errors, fn
      {:metadata, error} -> {:metadata_json, error}
      error -> error
    end)
  end

  defp map_entry_errors(errors) do
    Enum.map(errors, fn
      {:variable_values, error} -> {:variable_values_json, error}
      {:messages, error} -> {:messages_json, error}
      {:assertions, error} -> {:assertions_json, error}
      {:metadata, error} -> {:metadata_json, error}
      error -> error
    end)
  end

  defp error_text(errors) do
    Enum.map_join(errors, ", ", &CoreComponents.translate_error/1)
  end
end
