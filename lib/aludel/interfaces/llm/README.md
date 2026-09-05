# LLM Interfaces

Clean adapter pattern separating HTTP transport from provider logic.

## Structure

```
lib/aludel/interfaces/
├── adapters/http.ex           # Generic HTTP behaviour
├── llm.ex                      # LLM client (public API)
└── llm/
    ├── adapters/http/
    │   └── default.ex          # ReqLLM + telemetry
    ├── providers/
    │   ├── openai.ex
    │   ├── anthropic.ex
    │   ├── google.ex
    │   ├── ollama.ex
    │   ├── xai.ex
    │   ├── groq.ex
    │   └── openrouter.ex
    ├── behaviour.ex            # Provider contract
    ├── config.ex               # HTTP adapter + API key utils
    └── error_parser.ex
```

**Layers:**
- **HTTP** (`adapters/http/`): Transport, normalization, telemetry
- **Providers** (`llm/providers/`): Auth, validation
- **Utilities** (`config.ex`, `error_parser.ex`): Shared helpers

## Configuration

```elixir
# config/config.exs
config :aludel,
  http_client: Aludel.Interfaces.LLM.Adapters.Http.Default

# config/test.exs
config :aludel,
  http_client: Aludel.Interfaces.HttpClientMock
```

## Adding a Provider

Create a new provider module, e.g. `lib/aludel/interfaces/llm/providers/google.ex`:

```elixir
defmodule Aludel.Interfaces.LLM.Providers.Google do
  alias Aludel.Interfaces.LLM.{Config, ErrorParser}

  @behaviour Aludel.Interfaces.LLM.Behaviour

  @impl true
  def generate(model, prompt, config, opts) do
    with {:ok, api_key} <- Config.get_api_key(config) do
      req_opts =
        [api_key: api_key, temperature: config["temperature"] || 0.7]
        |> Keyword.merge(opts)

      case Config.http_adapter().request("google:#{model}", prompt, req_opts) do
        {:ok, response} -> {:ok, response}
        {:error, reason} -> ErrorParser.parse_error(reason)
      end
    end
  end
end
```

Register in `lib/aludel/interfaces/llm.ex`:

```elixir
@providers %{
  openai: OpenAI,
  anthropic: Anthropic,
  ollama: Ollama,
  google: Google,
  xai: XAI,
  groq: Groq,
  openrouter: OpenRouter
}
```

Provider credentials are loaded from application configuration. The supported environment
variables are `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`, `XAI_API_KEY`,
`GROQ_API_KEY`, and `OPENROUTER_API_KEY`. Ollama does not require an API key.
Provider records reject credential-shaped configuration keys recursively, and the execution
boundary sanitizes provider configuration before adding the runtime key.

## Swapping HTTP Client

Create adapter implementing `Aludel.Interfaces.Adapters.Http`:

```elixir
defmodule Aludel.Interfaces.LLM.Adapters.Http.HTTPoison do
  @behaviour Aludel.Interfaces.Adapters.Http

  @impl true
  def request(model_spec, prompt, opts) do
    # HTTP call, normalize response
    {:ok, %{content: "...", input_tokens: 0, output_tokens: 0}}
  end
end
```

Update config:

```elixir
config :aludel, http_client: Aludel.Interfaces.LLM.Adapters.Http.HTTPoison
```

## Telemetry Events

- `[:aludel, :llm, :http, :start]` - Request begins
- `[:aludel, :llm, :http, :stop]` - Request succeeds (includes tokens)
- `[:aludel, :llm, :http, :exception]` - Request fails

Example handler:

```elixir
:telemetry.attach_many("aludel-llm", [
  [:aludel, :llm, :http, :stop]
], fn [:aludel, :llm, :http, :stop], measurements, metadata, _ ->
  Logger.info("LLM call: #{metadata.model_spec}, tokens: #{measurements.input_tokens + measurements.output_tokens}")
end, nil)
```

## Design Principles

- Generic HTTP behaviour (not LLM-specific)
- No type leakage (providers never see library types)
- Dependency injection via config
- Mock at HTTP layer for tests
- Telemetry for observability
