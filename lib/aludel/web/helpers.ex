defmodule Aludel.Web.Helpers do
  @moduledoc false

  alias Phoenix.VerifiedRoutes

  @doc """
  Construct a path to a dashboard page with optional params.

  Routing is based on a socket and prefix tuple stored in the process dictionary.
  """
  def aludel_path(route, params \\ %{})

  def aludel_path(route, params) when is_list(route) do
    route
    |> Enum.join("/")
    |> aludel_path(params)
  end

  def aludel_path(route, params) do
    # Normalize route to prevent double slashes
    route = String.trim_leading(route, "/")

    params =
      params
      |> Enum.sort()
      |> encode_params()

    case Process.get(:routing) do
      {socket, prefix} ->
        path =
          case prefix do
            "/" -> "/#{route}"
            "" -> "/#{route}"
            _ -> "#{prefix}/#{route}"
          end

        VerifiedRoutes.unverified_path(socket, socket.router, path, params)

      :nowhere ->
        "/"

      nil ->
        raise RuntimeError, "nothing stored in the :routing key"
    end
  end

  @doc """
  Returns the icon path for a provider enum or provider struct.
  Accepts provider atoms or provider structs with a `:provider` field.
  """
  def provider_icon(%{provider: provider_enum}) when is_atom(provider_enum) do
    provider_icon(provider_enum)
  end

  def provider_icon(provider_enum) when is_atom(provider_enum) do
    case provider_enum do
      :openai -> "/images/open-ai-icon.svg"
      :anthropic -> "/images/anthropic-icon.svg"
      :ollama -> "/images/ollama-icon.svg"
      :google -> "/images/gemini-icon.svg"
      :xai -> "/images/grok-icon.svg"
      _ -> nil
    end
  end

  def provider_icon(_), do: nil

  # Private functions

  defp encode_params([]), do: []

  defp encode_params(params) do
    for {key, value} <- params do
      cond do
        value in [nil, ""] ->
          nil

        is_list(value) ->
          {key, Enum.join(value, ",")}

        true ->
          {key, value}
      end
    end
    |> Enum.reject(&is_nil/1)
  end
end
