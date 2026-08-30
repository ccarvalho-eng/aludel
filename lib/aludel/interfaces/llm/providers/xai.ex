defmodule Aludel.Interfaces.LLM.Providers.XAI do
  @moduledoc """
  xAI LLM provider implementation through ReqLLM.
  """

  alias Aludel.Interfaces.LLM.{Config, ErrorParser}

  @behaviour Aludel.Interfaces.LLM.Behaviour

  @impl true
  def generate(model, prompt, config, opts) do
    with {:ok, api_key} <- Config.get_api_key(config) do
      req_opts =
        [
          api_key: api_key,
          temperature: config["temperature"] || 0.7,
          max_tokens: config["max_tokens"] || 1024
        ]
        |> Keyword.merge(opts)

      case Config.http_adapter().request("xai:#{model}", prompt, req_opts) do
        {:ok, response} -> {:ok, response}
        {:error, reason} -> ErrorParser.parse_error(reason)
      end
    end
  end
end
