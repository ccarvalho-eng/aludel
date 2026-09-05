defmodule Aludel.Interfaces.LLM.Config do
  @moduledoc """
  Configuration utilities for LLM provider implementations.
  """

  alias Aludel.Interfaces.LLM.Adapters.Http

  @doc """
  Returns the configured HTTP adapter for making LLM API calls.
  """
  @spec http_adapter() :: module()
  def http_adapter do
    Application.get_env(:aludel, :http_client, Http.Default)
  end

  @doc """
  Extracts and validates the API key injected into request-scoped configuration.

  Returns `{:ok, key}` if valid, `{:error, :missing_api_key}` otherwise.
  """
  @spec get_api_key(map()) :: {:ok, String.t()} | {:error, :missing_api_key}
  def get_api_key(%{"api_key" => key}) when is_binary(key) and key != "",
    do: {:ok, key}

  def get_api_key(_), do: {:error, :missing_api_key}
end
