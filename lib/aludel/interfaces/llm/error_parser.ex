defmodule Aludel.Interfaces.LLM.ErrorParser do
  @moduledoc """
  Shared error parsing logic for LLM provider adapters.

  Normalizes HTTP errors to consistent error tuples across all providers.
  """

  @doc """
  Parses HTTP errors into standardized error tuples.

  ## Examples

      iex> parse_error(%{status: 401})
      {:error, {:auth_error, "Invalid API key"}}

      iex> parse_error(%{status: 429})
      {:error, {:rate_limit, nil}}
  """
  @spec parse_error(term()) ::
          {:error,
           {:auth_error, String.t()}
           | {:rate_limit, nil}
           | {:invalid_request, String.t()}
           | {:api_error, integer(), String.t()}
           | {:network_error, term()}}
  def parse_error(%{status: 401}), do: {:error, {:auth_error, "Invalid API key"}}

  def parse_error(%{status: 429}), do: {:error, {:rate_limit, nil}}

  def parse_error(%{status: status}) when status in [400, 404],
    do: {:error, {:invalid_request, "Invalid request"}}

  def parse_error(%{status: status} = error),
    do: {:error, {:api_error, status, inspect(error)}}

  def parse_error(reason), do: {:error, {:network_error, reason}}
end
