defmodule Aludel.Interfaces.LLM.Providers.Ollama do
  @moduledoc """
  Ollama API adapter implementation.

  Handles API communication with local Ollama models through the
  configured HTTP adapter.

  Ollama doesn't require authentication, so we mark the OpenAI-compatible
  backend explicitly for ReqLLM instead of sending placeholder credentials.
  """

  alias Aludel.Interfaces.LLM.{Config, ErrorParser}

  @behaviour Aludel.Interfaces.LLM.Behaviour

  @impl true
  def generate(model, prompt, config, opts) do
    opts = Keyword.delete(opts, :api_key)
    {provider_options, opts} = Keyword.pop(opts, :provider_options, [])

    req_opts =
      [
        base_url: "http://localhost:11434/v1",
        provider_options: ollama_provider_options(provider_options),
        temperature: config["temperature"] || 0.8
      ]
      |> maybe_put_max_tokens(config["max_tokens"])
      |> Keyword.merge(opts)

    model_spec = "openai:#{model}"

    case Config.http_adapter().request(model_spec, prompt, req_opts) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        ErrorParser.parse_error(reason)
    end
  end

  defp ollama_provider_options(provider_options) when is_list(provider_options) do
    Keyword.put(provider_options, :openai_compatible_backend, :ollama)
  end

  defp ollama_provider_options(nil), do: [openai_compatible_backend: :ollama]

  defp ollama_provider_options(provider_options) when is_map(provider_options) do
    Map.put(provider_options, :openai_compatible_backend, :ollama)
  end

  defp maybe_put_max_tokens(opts, nil) do
    opts
  end

  defp maybe_put_max_tokens(opts, max_tokens) do
    Keyword.put(opts, :max_tokens, max_tokens)
  end
end
