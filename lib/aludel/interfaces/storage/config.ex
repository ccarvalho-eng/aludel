defmodule Aludel.Storage.Config do
  @moduledoc """
  Resolves storage configuration without coupling adapters to the storage facade.

  Values declared as `{:system, variable}` are read from the process environment
  when configuration is requested. Nested keyword lists and maps are resolved
  recursively.
  """

  @type t :: keyword()

  # Keep the configuration key as data so adapters do not compile against the facade.
  @storage_config_key :"Elixir.Aludel.Storage"

  @doc """
  Returns the resolved storage configuration for the current application.
  """
  @spec get() :: t()
  def get do
    :aludel
    |> Application.get_env(@storage_config_key, [])
    |> resolve_system_values()
  end

  defp resolve_system_values(config) when is_list(config) do
    Enum.map(config, fn
      {key, {:system, env_var}} -> {key, System.get_env(env_var)}
      {key, value} -> {key, resolve_system_values(value)}
    end)
  end

  defp resolve_system_values(config) when is_map(config) do
    Map.new(config, fn {key, value} -> {key, resolve_system_values(value)} end)
  end

  defp resolve_system_values(value) do
    value
  end
end
