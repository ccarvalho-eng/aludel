# Embedding and Deployment Guide

Aludel can share a host Phoenix application's repository and authentication boundary, or run as a standalone dashboard.

## Requirements

- Elixir 1.17 or later
- Phoenix 1.8
- PostgreSQL 12 or later
- ImageMagick when PDF-to-image conversion is required

Aludel relies on PostgreSQL features including `JSONB`, `percentile_disc()`, and `DATE()` aggregations. SQLite and MySQL are not supported.

## Install in a Phoenix application

Add the dependency:

```elixir
def deps do
  [
    {:aludel, "~> 0.6.1"}
  ]
end
```

Configure the host repository:

```elixir
config :aludel, repo: MyApp.Repo
```

Copy and run Aludel's migrations:

```bash
mix aludel.install
mix ecto.migrate
```

The installer skips migration names already present in the host application, so it can be rerun after upgrading.

Mount the dashboard:

```elixir
use MyAppWeb, :router
import Aludel.Web.Router

scope "/admin" do
  pipe_through [:browser, :require_authenticated_user]

  aludel_dashboard "/aludel"
end
```

## Router options

`aludel_dashboard/2` accepts:

| Option | Default | Purpose |
|---|---|---|
| `:as` | `:aludel_dashboard` | Live session and route helper name |
| `:aludel_name` | `Aludel` | Instance label |
| `:resolver` | `Aludel.Web.Resolver` | User, access, and refresh policy |
| `:on_mount` | `[]` | Additional LiveView mount hooks run before Aludel authentication |
| `:socket_path` | `"/live"` | Host LiveView socket path |
| `:transport` | `"websocket"` | `"websocket"` or `"longpoll"` |
| `:logo_path` | `nil` | Link target for the dashboard logo |
| `:csp_nonce_assign_key` | `nil` | One assign key or a map of `:img`, `:style`, and `:script` nonce keys |

Example with a custom socket and CSP assignments:

```elixir
aludel_dashboard "/aludel",
  as: :llm_workbench,
  aludel_name: MyApp,
  socket_path: "/live",
  transport: "websocket",
  logo_path: "/admin",
  csp_nonce_assign_key: %{
    img: :img_nonce,
    style: :style_nonce,
    script: :script_nonce
  }
```

## Access resolver

Implement `Aludel.Web.Resolver` to connect the dashboard to the host user and authorization model:

```elixir
defmodule MyApp.AludelResolver do
  @behaviour Aludel.Web.Resolver

  @impl true
  def resolve_user(conn) do
    conn.assigns[:current_user]
  end

  @impl true
  def resolve_access(%{role: :admin}) do
    :all
  end

  def resolve_access(_user) do
    :read_only
  end

  @impl true
  def resolve_refresh(_user) do
    5
  end
end
```

Mount it with `resolver: MyApp.AludelResolver`. Full access enables mutations; read-only access keeps inspection workflows available. The refresh value is the polling interval in seconds used by result views.

Use the host router pipeline and `:on_mount` hooks for authentication. The resolver determines what an already authenticated user can do inside Aludel.

## Provider credentials

Configure only the providers you use:

```elixir
config :aludel, :llm,
  openai_api_key: System.get_env("OPENAI_API_KEY"),
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
  google_api_key: System.get_env("GOOGLE_API_KEY"),
  xai_api_key: System.get_env("XAI_API_KEY"),
  groq_api_key: System.get_env("GROQ_API_KEY"),
  openrouter_api_key: System.get_env("OPENROUTER_API_KEY")
```

Ollama does not require a key. Provider keys are read at runtime and are not persisted in provider records.

## Run concurrency

Native multi-provider runs are concurrent by default:

```elixir
config :aludel,
  run_execution_mode: :concurrent

config :aludel, :llm,
  max_concurrency: 5,
  request_timeout_ms: 120_000
```

The defaults are three concurrent calls and a 120-second request timeout. Set `run_execution_mode: :sequential` when provider calls must not overlap.

## Host-app callback execution

Callback mode evaluates the real host workflow instead of calling a provider directly:

```elixir
config :aludel,
  execution_mode: :callback,
  executor: MyApp.AludelExecutor
```

```elixir
defmodule MyApp.AludelExecutor do
  @behaviour Aludel.Executor

  @impl true
  def run(input) do
    case MyApp.AI.reply(%{
           question: input.variables["question"],
           messages: input.messages,
           documents: input.documents,
           model: input.provider && input.provider.model,
           trace_context: input.metadata
         }) do
      {:ok, reply} ->
        {:ok,
         %{
           output: reply.text,
           input_tokens: reply.input_tokens,
           output_tokens: reply.output_tokens,
           latency_ms: reply.latency_ms,
           cost_usd: reply.cost_usd,
           metadata: %{trace_id: reply.trace_id}
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

Only `output` is required on success. Omit token, latency, cost, or metadata fields when the host workflow does not provide them. The UI renders absent metrics as `N/A`.

## Document storage

Local development configuration:

```elixir
config :aludel, Aludel.Storage,
  adapter: Aludel.Interfaces.Storage.Adapters.Local,
  backends: [{Aludel.Interfaces.Storage.Adapters.Local, root: "tmp/aludel_uploads"}]
```

Standalone production selects AWS S3 or Google Cloud Storage through environment variables:

```bash
export ALUDEL_STORAGE_BACKEND=aws
export AWS_S3_BUCKET=aludel-uploads
export AWS_REGION=us-east-1
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
```

```bash
export ALUDEL_STORAGE_BACKEND=gcs
export GCS_BUCKET=aludel-uploads
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
export GCS_USER_PROJECT=optional-requester-pays-project
```

Inline `GOOGLE_APPLICATION_CREDENTIALS_JSON` is also supported. Applications can implement `Aludel.Interfaces.Storage.Behaviour` when documents must use another storage system.

## PDF conversion

Configure the included ImageMagick adapter when a provider needs page images instead of a native PDF:

```elixir
config :aludel, :document_converter,
  adapter: Aludel.Interfaces.DocumentConverter.Adapters.Imagemagick
```

The `convert` executable must be available to the running application. A custom adapter can implement `Aludel.Interfaces.DocumentConverter.Behaviour`.

## Standalone application

Run the repository's standalone app:

```bash
git clone https://github.com/ccarvalho-eng/aludel.git
cd aludel/standalone
mix deps.get
mix ecto.create
mix ecto.migrate
mix phx.server
```

Standalone production requires Basic Authentication. Generate a strong password and optionally enable read-only access:

```bash
export BASIC_AUTH_USER=admin
export BASIC_AUTH_PASS="$(openssl rand -base64 32)"
export READ_ONLY=true
```

Production startup rejects missing, partial, or blank credentials. Local development remains unauthenticated and listens only on loopback. `READ_ONLY=true` keeps the dashboard visible while server-side authorization blocks mutations and model requests.

Basic Authentication credentials require TLS in production. When a reverse proxy terminates TLS, preserve the `Authorization` header and keep the backend port private so clients cannot bypass the proxy.

## Docker Compose

From the repository root, copy `.env.example` to `.env`. Generate a strong database password with `openssl rand -hex 32`, paste it into `POSTGRES_PASSWORD`, configure the remaining required values, then start the database and release:

```bash
docker compose up -d
```

Compose rejects a missing or blank database password before startup. PostgreSQL is reachable only by services on the Compose network; it does not publish a host port. The web container receives separate database fields, waits for PostgreSQL, runs all migrations, and starts the standalone dashboard on the configured port.

For standalone production outside Compose, configure `DATABASE_URL` instead. Existing URL-based deployments remain supported.

### Upgrading an existing Compose database

PostgreSQL applies `POSTGRES_PASSWORD` only when it creates a new data volume. Existing deployments must rotate the current database role password through their established database-administration and secret-management process before switching to this version, then set the same value as `POSTGRES_PASSWORD` in the new `.env`.

Back up the database before the upgrade. Do not delete the `pgdata` volume because it contains the existing Aludel data.

## Demo catalog

For development and product exploration:

```bash
mix aludel.seed
```

The seed task is disabled in production. It builds a deterministic catalog covering all providers and major workflows, including datasets, suite history, artifacts, failures, and 60 days of analytics.
