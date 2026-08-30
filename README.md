<div align="left">
  <h1>Aludel - LLM Eval Workbench</h1>

  <p>
    <a href="https://hex.pm/packages/aludel"><img src="https://img.shields.io/hexpm/v/aludel.svg" alt="Hex.pm"/></a>
    <a href="https://github.com/ccarvalho-eng/aludel/actions/workflows/ci.yml"><img src="https://github.com/ccarvalho-eng/aludel/actions/workflows/ci.yml/badge.svg" alt="CI"/></a>
    <a href="https://hexdocs.pm/aludel"><img src="https://img.shields.io/badge/docs-hexdocs-purple" alt="Hex Docs"/></a>
    <a href="https://github.com/ccarvalho-eng/aludel/blob/main/LICENSE"><img src="https://img.shields.io/github/license/ccarvalho-eng/aludel" alt="License"/></a>
  </p>
</div>

Aludel gives teams a clean way to evaluate prompt and model behavior without inventing their own tooling first.

- Compare the same prompt across OpenAI, Anthropic, Gemini, and Ollama.
- Inspect output, latency, token usage, and cost side by side.
- Compare prompt versions and see pass-rate, cost, and latency changes over time.
- Run evaluation suites with assertions, document attachments, and CSV or JSON test case imports.
- Execute suites headlessly with machine-readable JSON output for CI workflows.
- Route runs and suites through your app's real LLM workflow with callback execution.
- Use it inside an existing Phoenix app or run it standalone.

## Why Aludel

Most teams evaluating LLM behavior end up with some combination of scripts, spreadsheets, and ad hoc dashboards. Aludel brings that work into one place with a UI that is practical enough for day-to-day iteration.

- **Provider comparison**: run the same input across models and vendors in one view.
- **Prompt history**: keep prompt changes traceable instead of losing them in copy-pasted variants.
- **Regression coverage**: turn important scenarios into repeatable suites with assertions.
- **Embedded app callbacks**: evaluate your production-facing workflow without rebuilding it in the dashboard.
- **Phoenix-native deployment**: mount it in your app or run it as a standalone dashboard.

## Structured Output Scoring

Suites support strict string assertions and structured JSON checks.

For structured outputs, use `json_deep_compare` to score partial matches instead of forcing all-or-nothing pass/fail outcomes.

```json
[
  {
    "type": "json_deep_compare",
    "expected": {
      "status": "ok",
      "customer": {
        "name": "Jane",
        "tier": "gold"
      }
    },
    "threshold": 75.0
  }
]
```

Aludel stores field-level comparison details, per-test match scores, and suite-run average scores so prompt evolution and exports can track structured output quality over time.

## Test Case Imports

Suite pages can import test cases from CSV or JSON. Aludel validates the file and shows a preview with row-level errors before saving any accepted test cases.

- JSON files contain an array of objects with `input`, `expected`, and `assertion` keys.
- CSV files use an `input,expected,assertion` header row and may include `notes`.

## Quick Start

### Embed in an existing Phoenix app

Requirements:
- Elixir and Phoenix
- PostgreSQL 12+

Aludel depends on PostgreSQL-specific features, including `JSONB`, `percentile_disc()`, and `DATE()`-based aggregations. SQLite and MySQL are not supported.

**1. Add the dependency**

```elixir
def deps do
  [
    {:aludel, "~> 0.5.1"}
  ]
end
```

```bash
mix deps.get
```

**2. Configure the repo**

```elixir
config :aludel, repo: YourApp.Repo
```

**3. Install and run migrations**

```bash
mix aludel.install
mix ecto.migrate
```

**4. Mount the dashboard**

```elixir
use YourAppWeb, :router
import Aludel.Web.Router

if Mix.env() == :dev do
  scope "/dev" do
    pipe_through :browser
    aludel_dashboard "/aludel"
  end
end
```

**5. Start using it**

Visit your configured path, for example `http://localhost:4000/dev/aludel`.

### Execution modes

Aludel supports two execution modes:

- **Native** (default): Aludel renders the prompt template and calls the configured provider directly.
- **App Callback**: your host app executes the real workflow and returns a normalized result back to Aludel.

Use callback mode when your production behavior includes orchestration beyond a single prompt, such as retrieval, tool usage, routing, retries, or post-processing.

Configure it in your embedded app:

```elixir
config :aludel,
  execution_mode: :callback,
  executor: MyApp.AludelExecutor
```

Example executor:

```elixir
defmodule MyApp.AludelExecutor do
  @behaviour Aludel.Executor

  @impl true
  def run(%{
        kind: kind,
        variables: variables,
        documents: documents,
        provider: provider,
        metadata: metadata
      }) do
    case MyApp.AI.reply(%{
           question: variables["question"],
           documents: documents,
           provider: provider && provider.provider,
           model: provider && provider.model,
           context: %{source: :aludel, kind: kind, metadata: metadata}
         }) do
      {:ok, reply} ->
        {:ok,
         %{
           output: reply.text,
           input_tokens: Map.get(reply, :input_tokens),
           output_tokens: Map.get(reply, :output_tokens),
           latency_ms: Map.get(reply, :latency_ms),
           cost_usd: Map.get(reply, :cost_usd),
           metadata: %{trace_id: Map.get(reply, :trace_id)}
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

Success responses only require `output`. `input_tokens`, `output_tokens`, `latency_ms`, `cost_usd`, and `metadata` are optional.

In callback mode, the existing run and suite UI stays the same:

- provider selection still stays available
- the run and suite screens show `Execution Mode`
- missing token or cost metrics render as `N/A`
- exports include callback metadata when present

### Headless suite execution

Run a suite from scripts or CI with stable JSON output:

```bash
mix aludel.eval \
  --suite-id SUITE_ID \
  --prompt-version-id PROMPT_VERSION_ID \
  --provider-id PROVIDER_ID
```

The task exits unsuccessfully when its arguments or targets are invalid, execution cannot complete, the suite has no test cases, or any test case fails.

### Standalone mode

If you want to run Aludel by itself:

```bash
git clone https://github.com/ccarvalho-eng/aludel.git
cd aludel/standalone
mix deps.get
mix ecto.create
mix ecto.migrate
mix phx.server
```

To populate the local database with sample prompts, providers, and suites:

```bash
mix aludel.seed
```

Visit `http://localhost:4000`.

To smoke-test callback mode in the standalone app, configure a local executor module in `standalone/lib/aludel_dash.ex` or another module loaded by the standalone app, then add:

```elixir
config :aludel,
  execution_mode: :callback,
  executor: AludelDash.Executor
```

After restarting `mix phx.server`, create a prompt version and provider in the UI, then:

1. Launch a run from `/runs/new?version=<prompt_version_id>`
2. Run a suite from `/suites/<suite_id>`
3. Confirm both screens show `Execution Mode`
4. Confirm the outputs come from your executor and optional metrics render cleanly when omitted

## Provider support

Aludel supports OpenAI, Anthropic, Google Gemini, and Ollama.

| Provider | API key required | Notes |
|---|---|---|
| OpenAI | Yes | Configure with `OPENAI_API_KEY` |
| Anthropic | Yes | Configure with `ANTHROPIC_API_KEY` |
| Google Gemini | Yes | Configure with `GOOGLE_API_KEY` |
| Ollama | No | Runs locally |

For embedded apps, configure provider keys in `config/runtime.exs`:

```elixir
# In config/runtime.exs
config :aludel, :llm,
  openai_api_key: System.get_env("OPENAI_API_KEY"),
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
  google_api_key: System.get_env("GOOGLE_API_KEY")
```

Ollama runs locally and does not require an API key.

Callback mode does not require Aludel to use those API keys directly, but provider selection still remains part of the current run and suite flows and is passed into the executor for host-app routing when needed.

## Document Storage

Uploaded test case documents go through `Aludel.Storage`. Documents can be attached while creating new suite test cases or while editing existing test cases.

- Development uses the local filesystem adapter from `config/dev.exs`.
- Production uses `config/runtime.exs` and requires `ALUDEL_STORAGE_BACKEND`.

### Development storage

Development stores uploaded documents on the local filesystem.

### Production storage

Set `ALUDEL_STORAGE_BACKEND` to `aws` or `gcs`.

For AWS S3:

```bash
export ALUDEL_STORAGE_BACKEND=aws
export AWS_S3_BUCKET=aludel-uploads
export AWS_REGION=us-east-1
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
```

For Google Cloud Storage:

```bash
export ALUDEL_STORAGE_BACKEND=gcs
export GCS_BUCKET=aludel-uploads
export GOOGLE_APPLICATION_CREDENTIALS=/absolute/path/to/service-account.json
```

If your GCS bucket requires requester-pays access, also set:

```bash
export GCS_USER_PROJECT=your-billing-project-id
```

The GCS adapter uses `Goth` with standard Google application credentials.
`GOOGLE_APPLICATION_CREDENTIALS_JSON` also works if you prefer inline JSON.

## Documentation

The README is intentionally optimized for first contact. For deeper setup, usage, and contribution details:

- [Wiki](https://github.com/ccarvalho-eng/aludel/wiki)
- [HexDocs](https://hexdocs.pm/aludel)
- [Contributing Guide](https://github.com/ccarvalho-eng/aludel/blob/main/CONTRIBUTING.md)
- [Issue Tracker](https://github.com/ccarvalho-eng/aludel/issues)
- [Discussions](https://github.com/ccarvalho-eng/aludel/discussions)

## Development

For local development:

```bash
mix deps.get
mix compile
mix test
mix precommit
```

If you are changing frontend assets:

```bash
mix assets.build
mix compile --force
```

For standalone development, run the app from the `standalone` directory:

```bash
cd standalone
mix phx.server
```

If you change frontend assets, rebuild them from the repo root and restart the standalone server:

```bash
mix assets.build
mix compile --force
```

## License

[Apache License 2.0](https://github.com/ccarvalho-eng/aludel/blob/main/LICENSE)
