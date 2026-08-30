defmodule Aludel.Web.DatasetLive.Index do
  @moduledoc """
  Lists and creates reusable evaluation datasets.
  """

  use Aludel.Web, :live_view

  alias Aludel.Datasets
  alias Aludel.Datasets.Params

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, stream_configure(socket, :datasets, dom_id: &"dataset-#{&1.id}")}
  end

  @impl Phoenix.LiveView
  def handle_params(_params, _uri, socket) do
    datasets = Datasets.list_datasets()

    {:noreply,
     socket
     |> assign(:page_title, "Datasets")
     |> assign(:datasets_empty?, datasets == [])
     |> assign(:dataset_form, dataset_form(Params.dataset_defaults()))
     |> stream(:datasets, datasets, reset: true)}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"dataset" => params}, socket) do
    {:noreply, assign(socket, :dataset_form, validated_dataset_form(params))}
  end

  @impl Phoenix.LiveView
  def handle_event("create", %{"dataset" => params}, socket) do
    with {:ok, attrs} <- Params.parse_dataset(params),
         {:ok, dataset} <- Datasets.create_dataset(attrs) do
      {:noreply,
       socket
       |> assign(:datasets_empty?, false)
       |> assign(:dataset_form, dataset_form(Params.dataset_defaults()))
       |> stream_insert(:datasets, dataset)
       |> put_flash(:info, "Dataset created")}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :dataset_form, dataset_form(params, changeset.errors))}

      {:error, errors} ->
        {:noreply, assign(socket, :dataset_form, dataset_form(params, errors))}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("delete", %{"id" => id}, socket) do
    case Datasets.get_dataset(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Dataset not found")}

      dataset ->
        case Datasets.delete_dataset(dataset) do
          {:ok, deleted} ->
            datasets_empty? = Datasets.list_datasets() == []

            {:noreply,
             socket
             |> assign(:datasets_empty?, datasets_empty?)
             |> stream_delete(:datasets, deleted)
             |> put_flash(:info, "Dataset deleted")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Dataset could not be deleted")}
        end
    end
  end

  defp validated_dataset_form(params) do
    case Params.parse_dataset(params) do
      {:ok, _attrs} -> dataset_form(params)
      {:error, errors} -> dataset_form(params, errors)
    end
  end

  defp dataset_form(params, errors \\ []) do
    to_form(params, as: :dataset, errors: errors)
  end
end
