# Curated Red-Team Datasets

`Aludel.RedTeam` turns a stable catalog of adversarial inputs into ordinary reusable dataset entries. This keeps security regressions in the same suite, reporting, quality-policy, UI, CLI, and ExUnit workflows as other evaluations.

The catalog aligns its categories with the [OWASP Top 10 for LLM Applications](https://genai.owasp.org/llm-top-10/) and the [NIST Generative AI Profile](https://nvlpubs.nist.gov/nistpubs/ai/NIST.AI.600-1.pdf). These cases are regression-test seeds, not a complete security assessment or compliance certification.

## Catalog

The core catalog currently contains:

| Case ID | Category | Severity | Technique | Recommended judge |
|---|---|---|---|---|
| `direct-instruction-override` | `prompt_injection` | critical | direct | refusal |
| `indirect-document-override` | `prompt_injection` | critical | indirect | refusal |
| `system-prompt-extraction` | `system_prompt_leakage` | high | direct | refusal |
| `private-record-disclosure` | `sensitive_information_disclosure` | critical | direct | PII |
| `unapproved-destructive-action` | `excessive_agency` | critical | direct | safety |
| `fabricated-citation` | `misinformation` | high | direct | hallucination |
| `concealed-security-disablement` | `unsafe_assistance` | high | direct | safety |

Inspect the complete catalog or one case without writing to the database:

```elixir
cases = Aludel.RedTeam.all()
categories = Aludel.RedTeam.categories()
{:ok, injection_case} = Aludel.RedTeam.fetch("direct-instruction-override")
```

Each template exposes its prompt, stable ID and version, category, severity, technique, risk reference, recommended judge template, canary, deterministic assertion, and SHA-256 template checksum.

## Materialize all cases

Create a reusable dataset, then materialize the catalog:

```elixir
{:ok, dataset} =
  Aludel.Datasets.create_dataset(%{
    name: "Security regressions",
    description: "Adversarial checks for the support assistant"
  })

{:ok, %{created: entries, skipped: []}} =
  Aludel.RedTeam.materialize(dataset)
```

The default prompt variable is `input`, so the target prompt should include `{{input}}`. Every entry receives a `not_contains` assertion for its unique canary. This provides a deterministic signal without another model call.

## Select categories or cases

Use category atoms for a risk-focused dataset:

```elixir
{:ok, %{created: injection_entries}} =
  Aludel.RedTeam.materialize(dataset,
    categories: [:prompt_injection, :system_prompt_leakage]
  )
```

Use stable IDs when you need individual cases, and set `:variable` when the target prompt uses another placeholder:

```elixir
{:ok, %{created: [entry]}} =
  Aludel.RedTeam.materialize(dataset,
    case_ids: ["fabricated-citation"],
    variable: "request"
  )
```

When both selectors are present, a case must match both.

## Add model-based judging

A deterministic canary catches direct compliance. Add the recommended rubric judge when you also want semantic evaluation of refusals, privacy protection, safety, or hallucination:

```elixir
{:ok, %{created: entries}} =
  Aludel.RedTeam.materialize(dataset,
    judge_provider_id: judge_provider.id,
    judge_threshold: 90
  )
```

The provider must be a configured provider UUID. The threshold accepts values from 0 through 100 and defaults to 80.

## Provenance and idempotency

Materialized entries store their catalog name and version, case ID and version, category, severity, technique, risk reference, recommended judge, template checksum, materialization checksum, deduplication key, and source under `metadata["red_team"]`.

The deduplication key represents the catalog case version and destination variable. Materialization locks the dataset for the transaction, preserving entry order when callers run concurrently. An entry whose payload and Aludel-owned provenance exactly match the catalog is returned in `skipped`; a different prompt variable creates a separate entry; different content or judge configuration under the same key returns `{:error, {:deduplication_conflict, key}}`.

```elixir
{:ok, %{created: created, skipped: []}} = Aludel.RedTeam.materialize(dataset)
{:ok, %{created: [], skipped: skipped}} = Aludel.RedTeam.materialize(dataset)

length(created) == length(skipped)
```

Materialization never updates or deletes existing entries.

## Use the entries

The catalog is exposed through the Elixir API. Its output is normal dataset data:

1. Inspect or edit the materialized dataset in the dashboard.
2. Populate a suite from the dataset in the dashboard or with `Aludel.Datasets.populate_suite/2`.
3. Run the suite in the dashboard, with `mix aludel.eval`, through ExUnit, or with `Aludel.Evals.execute_suite/4`.
4. Apply quality policies and reporters exactly as you would for any other suite.

There is no separate red-team CLI command or catalog browser in the dashboard in this release.
