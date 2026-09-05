defmodule Aludel.Interfaces.Storage.Adapters.GCS.GoogleApiClient do
  @moduledoc """
  Default GCS client implementation backed by `google_api_storage` and `Goth`.
  """

  @behaviour Aludel.Interfaces.Storage.Adapters.GCS.Client

  alias GoogleApi.Storage.V1.Api.Objects
  alias GoogleApi.Storage.V1.Connection
  alias GoogleApi.Storage.V1.Model.Object

  @impl true
  def put_object(bucket, key, data, content_type, config) do
    metadata = %Object{name: key, contentType: content_type}

    with {:ok, connection} <- connection(config),
         {:ok, _object} <-
           Objects.storage_objects_insert_iodata(
             connection,
             bucket,
             "multipart",
             metadata,
             data,
             request_options(config)
           ) do
      {:ok, key}
    end
  end

  @impl true
  def get_object(bucket, key, config) do
    with {:ok, connection} <- connection(config),
         {:ok, %Tesla.Env{body: body}} <-
           Objects.storage_objects_get(
             connection,
             bucket,
             key,
             [alt: "media"] ++ request_options(config),
             decode: false
           ) do
      {:ok, body}
    else
      {:ok, response} -> {:error, {:unexpected_response, response}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete_object(bucket, key, config) do
    with {:ok, connection} <- connection(config),
         {:ok, _response} <-
           Objects.storage_objects_delete(connection, bucket, key, request_options(config)) do
      :ok
    end
  end

  defp connection(config) do
    with {:ok, token} <- fetch_token(config) do
      {:ok, Connection.new(token)}
    end
  end

  defp fetch_token(config) do
    case Keyword.get(config, :goth) do
      nil ->
        {:error, :missing_goth_worker}

      goth_name ->
        case Goth.fetch(goth_name) do
          {:ok, %Goth.Token{token: token}} -> {:ok, token}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp request_options(config) do
    case Keyword.fetch(config, :user_project) do
      {:ok, user_project} -> [userProject: user_project]
      :error -> []
    end
  end
end
