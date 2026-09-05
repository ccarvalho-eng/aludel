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

- Compare the same prompt across OpenAI, Anthropic, Gemini, Ollama, xAI, Groq, and OpenRouter.
- Inspect output, latency, token usage, and cost side by side.
- Compare prompt versions and see pass-rate, cost, and latency changes over time.
- Run evaluation suites with deterministic assertions, model-based judges, repeated sampling, document attachments, and CSV or JSON test case imports.
- Assert generated output directly in ExUnit, or execute and gate persisted suites from application tests and CI.
- Execute suites headlessly from versioned JSON or YAML manifests with console, JSON, JUnit XML, or GitHub annotation reports.
- Route runs and suites through your app's real LLM workflow with callback execution.
- Reuse single-turn and multi-turn datasets across suites with provenance and metadata filtering.
- Materialize versioned prompt-injection, data-disclosure, unsafe-action, and misinformation checks from a curated red-team catalog, or generate bounded candidates for explicit review.
- Find quality, cost, latency, stability, and regression trade-offs with rolling analytics and Pareto analysis.
- Generate failure-grounded prompt suggestions, then explicitly accept or dismiss them.
- Use it inside an existing Phoenix app or run it standalone.

## Why Aludel

Most teams evaluating LLM behavior end up with some combination of scripts, spreadsheets, and ad hoc dashboards. Aludel brings that work into one place with a UI that is practical enough for day-to-day iteration.

- **Provider comparison**: run the same input across models and vendors in one view.
- **Prompt history**: keep prompt changes traceable instead of losing them in copy-pasted variants.
- **Regression coverage**: turn important scenarios into repeatable suites with assertions.
- **Embedded app callbacks**: evaluate your production-facing workflow without rebuilding it in the dashboard.
- **Phoenix-native deployment**: mount it in your app or run it as a standalone dashboard.

## UI, CLI, and Library APIs

| Interface | Use it for |
|---|---|
| Dashboard UI | Create and version prompts; configure providers; compare models; manage reusable and materialized red-team datasets and documents; author assertions, judges, and quality policies; run and retry suites; inspect evaluator evidence; analyze cost, latency, stability, regressions, and Pareto frontiers; review prompt suggestions; export results |
| Mix CLI | Install Aludel with `mix aludel.install`; create deterministic demo data with `mix aludel.seed`; execute persisted suites by IDs or versioned JSON/YAML manifests with `mix aludel.eval`; emit console, JSON, JUnit, or GitHub Actions reports for local scripts and CI gates |
| Elixir APIs | Embed the dashboard in a Phoenix router; route execution through host callbacks; create and execute prompts, datasets, suites, policies, and reports; materialize curated red-team cases; generate and review targeted adversarial candidates; load file-based suites; add custom metrics and reporters; assert evaluations directly from ExUnit |

The dashboard and automation interfaces use the same persisted prompts, providers, datasets, suites, runs, quality policies, and evaluation evidence. A workflow can be authored in the UI, committed as a suite manifest, gated from the CLI, and inspected again in the dashboard without maintaining a second test-case format.

## Feature Catalog

| Area | Features |
|---|---|
| Dashboard | Rolling 7-day and 30-day comparisons, lifetime totals, activity history, recent evaluations, pass rates, weighted quality, cost efficiency, latency efficiency, stability, and regression signals |
| Prompts | `{{variable}}` templates, immutable versions, tags, search, pagination, typed projects, version diffs, and provider-specific evolution history |
| Providers | OpenAI, Anthropic, Google Gemini, Ollama, xAI, Groq, and OpenRouter; active and deprecated text-model discovery; custom model IDs; built-in or overridden pricing |
| Runs | Multi-provider execution, concurrent or sequential dispatch, live status updates, partial-failure handling, normalized execution artifacts, result copy actions, and JSON exports |
| Evaluation suites | Visual and JSON test-case editing, contextual prompt and execution evidence, normalized evaluator details, immutable versioned quality policies, single-turn and multi-turn inputs, bounded repeated sampling with configurable pass reducers, document attachments, suite history, per-result retries, and aggregate quality, cost, and latency |
| Assertions | `contains`, `not_contains`, `regex`, `exact_match`, typed `json_field`, scored `json_deep_compare`, custom rubric judges, and seven versioned judge templates |
| Imports and datasets | CSV and JSON import previews with row-level errors; reusable ordered datasets with variables, messages, assertions, metadata filters, provenance, idempotent suite population, and a versioned red-team catalog with deterministic deduplication |
| Prompt evolution | Version and provider trends, version-over-version deltas, suite-scoped Pareto frontiers, failure-grounded prompt suggestions, and explicit accept or dismiss decisions |
| Automation and exports | Native ExUnit assertions and persisted suite gates, versioned JSON or YAML suite manifests, JSON run and suite exports, CSV or JSON evolution exports, a custom reporter behavior, console reports, versioned JSON, JUnit XML, GitHub annotations, and policy-aware `mix aludel.eval` quality gates |
| Execution and extension | Native provider calls, host-app callback execution, pluggable LLM, storage, and document-conversion boundaries, optional callback metadata, and configurable run concurrency |
| Deployment | Embedded Phoenix dashboard, standalone app, Docker Compose, local/AWS S3/GCS document storage, custom auth/access resolvers, CSP nonce support, theming, and read-only mode |
| Demo data | Deterministic prompts, providers, datasets, suites, runs, failures, artifacts, and 60 days of comparison history through `mix aludel.seed` |

See the [complete feature guide](https://hexdocs.pm/aludel/features.html) for behavior, constraints, and examples.

## Model-Based Evaluation

Use a rubric judge when correctness depends on meaning instead of an exact string or JSON shape. Choose a separate configured provider for the judge and use either a custom rubric or a versioned built-in template:

```json
[
  {
    "type": "rubric_judge",
    "template": "faithfulness",
    "provider_id": "00000000-0000-0000-0000-000000000000",
    "threshold": 85,
    "context": "Claims must be supported by this grounding evidence."
  }
]
```

Replace the placeholder with the ID of a configured provider.

The catalog includes correctness, relevance, faithfulness, safety, refusal quality, PII protection, and hallucination checks. Aludel records the resolved rubric and template version alongside score, reasoning, duration, provider, model, token usage, cost, and structured evaluator status.

See the [evaluation guide](https://hexdocs.pm/aludel/evaluations.html#custom-rubric-judge), [rubric judge guide](https://github.com/ccarvalho-eng/aludel/wiki/Rubric-Judges), and [judge catalog](https://github.com/ccarvalho-eng/aludel/wiki/Judge-Catalog).

Suite execution supplies metrics with normalized output, rendered input, prompt template, variables, messages, documents, metadata, provider, prompt version, and execution evidence. Expected references remain available in assertion configuration, and direct callers can also set `expected` on `Aludel.Evals.Metric.Context`. See [metric context](https://github.com/ccarvalho-eng/aludel/wiki/Metric-Context) and [evaluator execution details](https://github.com/ccarvalho-eng/aludel/wiki/Evaluator-Execution-Details).

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

## Repeated Evaluation Sampling

Nondeterministic model output can make a single response misleading. Run each test case up to 20 times and reduce the ordered attempts into one result:

```elixir
{:ok, suite_run} =
  Aludel.Evals.execute_suite(suite, prompt_version, provider,
    samples: 5,
    reducer: {:minimum_pass_rate, 0.8}
  )
```

Reducers support `:all`, `:any`, strict `:majority`, and a minimum pass rate. Aludel retains every attempt, sums token usage, cost, and latency, and reruns the complete sampling configuration when a result is retried.

See the [evaluation guide](https://hexdocs.pm/aludel/evaluations.html#repeat-nondeterministic-cases) and [repeated sampling wiki guide](https://github.com/ccarvalho-eng/aludel/wiki/Repeated-Sampling) for the full result shape and reducer examples.

## Curated Red-Team Datasets

Materialize a versioned set of adversarial cases into any reusable dataset:

```elixir
{:ok, dataset} = Aludel.Datasets.create_dataset(%{name: "Security regressions"})

{:ok, %{created: created, skipped: skipped}} =
  Aludel.RedTeam.materialize(dataset,
    categories: [:prompt_injection, :system_prompt_leakage],
    judge_provider_id: judge_provider.id,
    judge_threshold: 90
  )
```

Each curated entry includes a deterministic canary assertion plus optional model-based judging. Metadata records its stable case ID, catalog and case versions, risk category, severity, technique, source, checksum, and deduplication key. Repeating the same materialization skips matching entries; conflicting content or judge configuration returns an error.

Generate cases for a product-specific context without writing to the database, then inspect the returned candidates and failures before deciding which cases belong in an evaluation dataset:

```elixir
{:ok, generation} =
  Aludel.RedTeam.generate(generator_provider.id,
    categories: [:prompt_injection, :sensitive_information_disclosure],
    target_context: "A support assistant may read account history but must not reveal credentials",
    cases_per_category: 2,
    max_requests: 2,
    max_total_tokens: 8_000,
    max_cost_usd: 1.00
  )
```

Generation is bounded by category count, cases per category, context size, requests, output tokens, observed total tokens, observed cost, response size, and per-request timeout. Valid categories remain reviewable when another category fails. Each candidate and the complete generation carry checksums for stable review. Usage is observed from successful provider responses; failed or timed-out external requests may still incur provider-side usage that Aludel cannot report.

After reviewing the candidates, explicitly approve their stable IDs and import them atomically:

```elixir
approved_case_ids =
  generation.cases
  |> Enum.filter(&approved_by_reviewer?/1)
  |> Enum.map(& &1.id)

{:ok, %{created: created, skipped: skipped}} =
  Aludel.RedTeam.import_generated(dataset, generation,
    approved_case_ids: approved_case_ids
  )
```

Import revalidates the generation and candidate checksums, requires at least one unique approved ID, attaches each candidate's recommended rubric judge, records generation and review provenance, and skips only an exact prior import. Any conflict rolls back the complete approved selection.

Catalog materialization and generated-case generation, review, and import are Elixir API features. Persisted cases use the normal dataset and suite workflows in the dashboard, `mix aludel.eval`, ExUnit, and the library API. There is no separate red-team CLI command or generation/import form in the dashboard yet.

See the [red-team guide](https://hexdocs.pm/aludel/red_team.html), [curated datasets wiki guide](https://github.com/ccarvalho-eng/aludel/wiki/Red-Team-Datasets), and [generated cases wiki guide](https://github.com/ccarvalho-eng/aludel/wiki/Generated-Red-Team-Cases) for category filters, review, budgets, provenance, and rerun behavior.

## Versioned Quality Policies

Define what a suite must satisfy instead of treating every run as an all-or-nothing test count:

```elixir
{:ok, policy} =
  Aludel.Evals.create_suite_policy(suite, %{
    "schema_version" => 1,
    "rules" => [
      %{"id" => "overall", "type" => "overall_pass_rate", "minimum" => 0.95},
      %{
        "id" => "priority",
        "type" => "metadata_pass_rate",
        "metadata" => %{"priority" => "high"},
        "minimum" => 1.0
      },
      %{"id" => "budget", "type" => "total_cost_usd", "maximum" => 0.50}
    ]
  })
```

Policies can gate overall pass rate, metadata groups, evaluator scores, total cost, and average latency. Each update creates an immutable suite-local version. A run snapshots the latest version before execution, and retries continue to use that same version.

Policy results report `passed`, `failed`, `invalid`, or `unavailable`; missing evidence never silently passes. `mix aludel.eval` uses the policy outcome as its exit gate and preserves the legacy all-cases-must-pass behavior for suites without a policy.

See the [evaluation guide](https://hexdocs.pm/aludel/evaluations.html#enforce-a-versioned-quality-policy) and [quality policies wiki guide](https://github.com/ccarvalho-eng/aludel/wiki/Quality-Policies) for every rule and result example.

## Evaluation Reporters

Render the same persisted suite result for local review, API consumers, and CI systems without coupling those formats to persistence:

```elixir
alias Aludel.Evals.Reporter

console = Reporter.render!(suite_run, :console)
json = Reporter.render!(suite_run, :json, pretty: true)
junit_xml = Reporter.render!(suite_run, :junit)
github_annotations = Reporter.render!(suite_run, :github)
```

`Aludel.Evals.Report` defines the stable schema-version-2 model. Built-in reporters cover concise console text, JSON interchange, JUnit test reports, and GitHub Actions annotations. Custom modules can implement the `Aludel.Evals.Reporter` behavior.

The GitHub reporter escapes and bounds untrusted evaluator text before emitting workflow commands. JUnit output escapes identifiers and reasons, omits model output by default, and represents a policy-only rejection as a failed test case. Pass `include_output: true` or `--include-output` only when the target artifact is appropriate for generated responses.

See the [reporter guide](https://hexdocs.pm/aludel/reporters.html) and [evaluation reporters wiki guide](https://github.com/ccarvalho-eng/aludel/wiki/Evaluation-Reporters) for CLI, library, CI, and custom reporter examples.

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
    {:aludel, "~> 0.6.1"}
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
- normalized execution artifacts record the request shape, execution mode, output, metrics, and bounded error details

Native multi-provider runs execute concurrently by default, with a maximum concurrency of three and a 120-second timeout. Hosts can choose sequential execution or tune those limits:

```elixir
config :aludel,
  run_execution_mode: :concurrent

config :aludel, :llm,
  max_concurrency: 5,
  request_timeout_ms: 120_000
```

Set `run_execution_mode: :sequential` when provider calls must not overlap.

### Headless suite execution

Keep the execution target and sampling policy in a versioned manifest while the suite's test cases and dataset provenance remain in Aludel:

```yaml
schema_version: 1
suite_id: 9a756a58-eaec-43ca-99e6-f5c016d85d0c
prompt_version_id: e74cf2e1-94b6-4bcb-9ed9-b259661be906
provider_id: e1c60ec0-6d55-419b-b958-7d088055254f
sampling:
  samples: 5
  reducer: majority
```

Run it from scripts or CI:

```bash
mix aludel.eval --file evals/support-answer.yaml
```

JSON manifests use the same schema. You can also supply the three identifiers directly:

```bash
mix aludel.eval \
  --suite-id SUITE_ID \
  --prompt-version-id PROMPT_VERSION_ID \
  --provider-id PROVIDER_ID
```

Select another reporter and optionally write it directly to a file:

```bash
mix aludel.eval \
  --suite-id SUITE_ID \
  --prompt-version-id PROMPT_VERSION_ID \
  --provider-id PROVIDER_ID \
  --format junit \
  --output aludel-junit.xml
```

Supported formats are `console`, `json`, `junit`, and `github`; `--pretty` formats JSON for human review, while `--include-output` opts JUnit into generated responses. The task exits unsuccessfully when its arguments or targets are invalid, execution cannot complete, the suite is empty, or the active quality gate does not pass.

The versioned `aludel_eval` JSON envelope includes suite and provider identifiers, aggregate and total score/cost/latency data, quality-policy evidence, and individual assertion results.

See the [file-based suite guide](https://hexdocs.pm/aludel/file_suites.html) and [wiki examples](https://github.com/ccarvalho-eng/aludel/wiki/File-Based-Suites) for both formats, every sampling reducer, library execution, validation behavior, and CI usage.

### ExUnit evaluation assertions

Use `Aludel.ExUnit` to keep focused model checks beside application tests:

```elixir
defmodule MyApp.AnswerTest do
  use ExUnit.Case
  use Aludel.ExUnit

  test "answers with the expected city" do
    output = MyApp.answer("What is the capital of France?")

    assert_evaluation(output, %{
      "type" => "exact_match",
      "value" => "Paris"
    })
  end
end
```

Use `assert_evaluations/2` for several metrics, `assert_suite_run/1` for an existing persisted result, or `assert_suite/3` and `assert_suite/4` to execute, persist, and gate a suite. Stored quality policies determine the effective suite status when present; otherwise every case must pass and empty runs fail. Failure messages include bounded metric, case, and policy evidence without copying generated output into test logs.

See the [ExUnit evaluation guide](https://hexdocs.pm/aludel/ex_unit.html) and [ExUnit wiki examples](https://github.com/ccarvalho-eng/aludel/wiki/ExUnit-Evaluations).

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

To populate the local database with realistic prompts, providers, datasets, suites, AI-like
results, and 60 days of comparison history:

```bash
mix aludel.seed
```

Visit `http://localhost:4000`.

The standalone release also supports optional HTTP Basic Authentication and read-only access:

```bash
export BASIC_AUTH_USER=admin
export BASIC_AUTH_PASS=change-me
export READ_ONLY=true
```

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

Aludel supports OpenAI, Anthropic, Google Gemini, Ollama, xAI, Groq, and OpenRouter.

| Provider | API key required | Notes |
|---|---|---|
| OpenAI | Yes | Configure with `OPENAI_API_KEY` |
| Anthropic | Yes | Configure with `ANTHROPIC_API_KEY` |
| Google Gemini | Yes | Configure with `GOOGLE_API_KEY` |
| Ollama | No | Runs locally |
| xAI | Yes | Configure with `XAI_API_KEY` |
| Groq | Yes | Configure with `GROQ_API_KEY` |
| OpenRouter | Yes | Configure with `OPENROUTER_API_KEY` |

Provider forms discover active text-generation models from LLMDB, keep deprecated models available when editing existing configurations, and allow custom model IDs. Token costs use built-in per-model rates when available; custom input and output rates can be configured per provider.

For embedded apps, configure provider keys in `config/runtime.exs`:

```elixir
# In config/runtime.exs
config :aludel, :llm,
  openai_api_key: System.get_env("OPENAI_API_KEY"),
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
  google_api_key: System.get_env("GOOGLE_API_KEY"),
  xai_api_key: System.get_env("XAI_API_KEY"),
  groq_api_key: System.get_env("GROQ_API_KEY"),
  openrouter_api_key: System.get_env("OPENROUTER_API_KEY")
```

Ollama runs locally and does not require an API key.

Callback mode does not require Aludel to use those API keys directly, but provider selection still remains part of the current run and suite flows and is passed into the executor for host-app routing when needed.

## Document Storage

Uploaded test case documents go through `Aludel.Storage`. Documents can be attached while creating new suite test cases or while editing existing test cases.

Supported uploads are PDF, PNG, JPEG, JSON, CSV, and plain text. Anthropic accepts PDFs natively; adapters that require images can use the configurable ImageMagick converter.

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

## Evaluation Workflows

Test cases can be authored in the visual assertion editor or as JSON. Suites support inline editing, document management, execution history, detailed assertion results, and retrying an individual failed result without rerunning the entire suite.

Reusable datasets hold ordered single-turn or multi-turn entries. Each entry can include template variables, conversation messages, assertions, and arbitrary JSON metadata. Dataset pages support metadata filtering, and suite population preserves source provenance while skipping entries that were already imported into that suite.

Prompt evolution combines suite history across versions and providers. The UI shows pass rate, structured-output score, cost, latency, version-over-version deltas, regression and stability signals, and a suite-scoped Pareto frontier. A failure reflection workflow can ask the selected provider for a variable-preserving prompt suggestion; accepting it creates a new immutable prompt version, while dismissal keeps the decision in history.

## Documentation

The README is intentionally optimized for first contact. For deeper setup, usage, and contribution details:

- [Feature Guide](https://hexdocs.pm/aludel/features.html)
- [Evaluation Guide](https://hexdocs.pm/aludel/evaluations.html)
- [Reporter Guide](https://hexdocs.pm/aludel/reporters.html)
- [Embedding Guide](https://hexdocs.pm/aludel/embedding.html)
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
