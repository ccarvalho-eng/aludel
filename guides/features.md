# Feature Guide

Aludel is a Phoenix-native workbench for comparing LLM behavior, building regression suites, and tracing prompt quality across versions, providers, cost, and latency.

## Dashboard

The dashboard combines recent and lifetime activity:

- rolling 7-day and 30-day comparisons
- total executions, pass rate, weighted quality, total cost, cost per run, average latency, P50, and P95
- outcome-weighted cost and latency efficiency
- pass-rate stability and regression signals
- interactive activity history
- cost breakdowns by provider or prompt
- latency and pass-rate breakdowns
- recent evaluations and quick actions

Rolling metrics use complete evaluation history inside the selected window. Lifetime cards remain available as context when recent traffic is sparse.

## Prompts and projects

Prompts are stable records with immutable template versions. Aludel extracts `{{variable}}` placeholders automatically and asks for values when a run starts.

Prompt management includes:

- names, descriptions, tags, search, tag filters, and pagination
- typed prompt projects with create, rename, filter, expand, and delete workflows
- immutable prompt versions and a version-history rail
- side-by-side template diffs
- links from every prompt to run and evolution workflows

Suite projects are separate from prompt projects so each catalog can be organized independently.

## Providers and models

Aludel supports OpenAI, Anthropic, Google Gemini, Ollama, xAI, Groq, and OpenRouter.

Provider forms:

- discover active text-generation and chat models from LLMDB
- retain deprecated models for existing configurations
- accept custom model IDs
- store JSON generation configuration for temperature and output limits
- use built-in per-model token pricing or custom input/output rates

Provider credentials come from application configuration or environment variables and are not stored in provider rows. Ollama does not require an API key and resolves to free token pricing by default.

## Runs

A run applies one prompt version and one variable set to one or more providers. Multi-provider runs execute concurrently by default and can be configured for sequential dispatch.

Each provider result tracks:

- pending, running, completed, or error state
- raw output and a parsed JSON representation when possible
- input/output tokens, latency, estimated cost, and callback metadata
- a normalized execution artifact describing mode, inputs, documents, output, metrics, and bounded errors

The run page receives live status updates, handles partial provider failure, supports copying output or errors, and exports individual results as JSON.

## Evaluation suites

Suites bind repeatable test cases to a prompt. Test cases can use template variables, multi-turn messages, document attachments, and one or more assertions.

The suite UI supports:

- visual and raw JSON assertion editors
- inline suite metadata and test-case editing
- CSV and JSON imports with preview and row-level validation
- population from reusable datasets
- selection of a prompt version and provider for each suite run
- persisted suite-run history with aggregate pass/fail, quality score, cost, and latency
- detailed assertion and field-comparison results
- retrying one test result without rerunning the entire suite
- copy actions and raw JSON exports

Built-in metrics are `contains`, `not_contains`, `regex`, `exact_match`, `json_field`, and `json_deep_compare`. See the [Evaluation Guide](evaluations.md) for examples.

## Reusable datasets

Datasets are ordered collections of evaluation examples that can be reused by multiple suites. A dataset entry can contain:

- a name and explicit position
- prompt variable values
- single-turn or multi-turn messages
- assertions
- arbitrary JSON metadata

Dataset pages support create, edit, delete, entry management, and JSON containment filters over metadata. Populating a suite copies entries in order, records source provenance, and skips entries already imported from that dataset.

## Documents and storage

Suite test cases accept PDF, PNG, JPEG, JSON, CSV, and plain-text attachments. File signatures and content are validated before persistence.

Document bytes are kept outside PostgreSQL through `Aludel.Storage`; database rows retain metadata and storage references. Included adapters cover:

- local filesystem storage for development
- AWS S3
- Google Cloud Storage, including requester-pays buckets

Anthropic can receive PDFs natively. Providers that require images can use the configurable ImageMagick PDF converter.

## Prompt evolution and optimization

Evolution analysis derives version-level and provider-level metrics from suite history:

- pass rate and structured-output score
- average and exact aggregate cost and latency
- cost and latency per passed test
- version-over-version deltas
- pass-rate standard deviation and stability sample size
- bounded regression, improvement, and insufficient-data signals
- suite-scoped Pareto frontiers across quality, cost, and latency

The failure-reflection workflow uses failed suite evidence to request a variable-preserving prompt suggestion from a selected provider. Suggestions remain pending until a user explicitly accepts or dismisses them. Acceptance creates a new immutable prompt version and preserves the decision trail.

## Exports and CI

Aludel provides:

- JSON exports for individual run results
- JSON exports for suite runs, including assertions, retries, callback metadata, and artifacts
- JSON and CSV exports for prompt evolution metrics and provider breakdowns
- `mix aludel.eval` for headless suite execution

The Mix task emits a versioned `aludel_eval` JSON envelope and exits unsuccessfully for invalid targets, execution errors, empty suites, or failed test cases. This makes the task suitable for CI quality gates.

## Execution modes

Native mode renders the prompt and calls the selected provider adapter. Callback mode delegates to a host module implementing `Aludel.Executor`, allowing evaluations to exercise retrieval, tools, routing, retries, or post-processing from the real application.

Both modes use the same run and suite UI. Callback responses require only `output`; tokens, latency, cost, and metadata are optional.

## Embedding, access, and deployment

Aludel can be mounted inside a Phoenix router, run from the standalone application, or started with Docker Compose.

The embedded dashboard supports:

- custom route names and instance names
- custom auth/access resolvers and additional `on_mount` hooks
- full-access or read-only operation
- configurable refresh interval, LiveView socket path, and websocket/longpoll transport
- custom logo links and CSP nonce assign keys
- self-contained versioned CSS and JavaScript plus packaged fonts, icons, and images
- light, dark, and system themes

The standalone release adds optional HTTP Basic Authentication and read-only mode. See the [Embedding Guide](embedding.md) for configuration.

## Demo data

`mix aludel.seed` creates deterministic development data and is disabled in production. The catalog includes prompts, 14 configurations across all seven providers, datasets, suites, individual runs, suite runs, structured artifacts, representative failures, and 60 days of analytics history.

Running the task again refreshes the deterministic demo catalog instead of producing unrelated random examples.

## Extension points

The public boundaries support host-specific integrations:

- `Aludel.Executor` for application callback execution
- `Aludel.Interfaces.LLM.Behaviour` for LLM adapters
- `Aludel.Interfaces.Storage.Behaviour` for document storage
- `Aludel.Interfaces.DocumentConverter.Behaviour` for document conversion
- `Aludel.Evals.Metric` and its registry for evaluation metric implementations

For operational examples, continue with the [Evaluation Guide](evaluations.md) and [Embedding Guide](embedding.md).
