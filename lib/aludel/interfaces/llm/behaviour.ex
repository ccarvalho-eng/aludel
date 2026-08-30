defmodule Aludel.Interfaces.LLM.Behaviour do
  @moduledoc """
  Behaviour for LLM provider implementations.

  Each provider must implement `generate/4` to handle text generation
  with provider-specific logic (authentication, configuration, etc.).
  """

  @type response :: %{
          content: String.t(),
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer()
        }

  @type error_reason ::
          :missing_api_key
          | {:auth_error, String.t()}
          | {:rate_limit, non_neg_integer() | nil}
          | {:invalid_request, String.t()}
          | {:api_error, non_neg_integer(), String.t()}
          | {:network_error, term()}

  @doc """
  Generates text using the LLM provider.

  ## Parameters
    - model: Model identifier (e.g., "gpt-4o", "claude-3-5-sonnet")
    - prompt: Text prompt or normalized conversation messages to send to the model
    - config: Provider configuration (API keys, temperature, etc.)
    - opts: Additional options (e.g., documents for vision models)

  ## Returns
    - `{:ok, response}` with content and token usage
    - `{:error, reason}` if generation fails
  """
  @callback generate(
              model :: String.t(),
              prompt :: String.t() | [map()],
              config :: map(),
              opts :: keyword()
            ) ::
              {:ok, response()} | {:error, error_reason()}
end
