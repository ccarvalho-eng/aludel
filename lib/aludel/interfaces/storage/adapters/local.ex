defmodule Aludel.Interfaces.Storage.Adapters.Local do
  @moduledoc """
  Local filesystem adapter for document storage.
  """

  @behaviour Aludel.Interfaces.Storage.Behaviour

  alias Aludel.Storage.Config

  @default_root Path.join(System.tmp_dir!(), "aludel-storage")

  @impl true
  def put(key, data, _content_type, config) do
    path = path_for(key, config)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, data) do
      {:ok, key}
    end
  end

  @impl true
  def get(key, config) do
    key
    |> path_for(config)
    |> File.read()
  end

  @impl true
  def delete(key, config) do
    key
    |> path_for(config)
    |> File.rm()
    |> case do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec path_for(String.t()) :: String.t()
  def path_for(key) do
    path_for(key, Config.get())
  end

  @spec path_for(String.t(), keyword()) :: String.t()
  def path_for(key, config) do
    root =
      config
      |> Keyword.get(:root, @default_root)
      |> Path.expand()

    path = Path.expand(key, root)

    if path == root or String.starts_with?(path, root <> "/") do
      path
    else
      raise ArgumentError, "invalid storage key path"
    end
  end
end
