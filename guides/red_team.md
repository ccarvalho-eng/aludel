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

## Generated cases

Use an existing provider to propose cases for a product, policy, or threat context. Generation returns an in-memory `Aludel.RedTeam.Generation` and does not write to a dataset:

```elixir
{:ok, generation} =
  Aludel.RedTeam.generate(generator_provider.id,
    categories: [:prompt_injection, :sensitive_information_disclosure],
    target_context: "A support assistant may read account history but must not reveal credentials",
    cases_per_category: 2,
    max_requests: 2,
    max_output_tokens: 1_200,
    max_total_tokens: 8_000,
    max_cost_usd: 1.00,
    request_timeout_ms: 30_000
  )
```

The default request generates two prompt-injection candidates. Category lists must be non-empty and unique. Aludel allows at most six category requests, five cases per category, 4,000 output tokens per request, 100,000 observed total tokens, USD 100 of observed cost, 10,000 context characters, 100,000 response bytes, and 120 seconds per request. Lower defaults are applied when an option is omitted.

The total-token and cost values are stop thresholds based on provider-reported usage. Aludel checks them before starting the next category, so the final in-flight request can report usage above a threshold; the context-size and per-request output-token limits bound that overshoot. The request count and timeout are hard per-call limits. Failed or timed-out external requests may still incur provider-side usage that Aludel cannot observe because no usage response was returned. Calling `generate/2` again starts a new set of requests; Aludel does not retry categories automatically.

### Review the result

Generation runs once per selected category. Its status is `:completed`, `:partial_failure`, or `:failed`. Validated cases remain available if a provider request times out, fails, exceeds a budget before another category starts, or returns invalid structured output.

```elixir
Enum.each(generation.cases, fn candidate ->
  IO.inspect(%{
    id: candidate.id,
    category: candidate.category,
    severity: candidate.severity,
    prompt: candidate.prompt,
    rationale: candidate.rationale,
    recommended_judge: candidate.recommended_judge
  })
end)

IO.inspect(generation.failures)
IO.inspect(generation.usage)
IO.inspect(generation.limits)
```

Failures contain only the category, stable failure type, and a safe message. Raw provider errors and malformed model output are not retained. The raw target context is represented by a checksum in the generation result. Each candidate and the complete generation record have checksums for stable review.

Generation deliberately stops at the review boundary: it does not create, update, delete, or execute dataset entries. Use the candidate prompt, rationale, category, severity, technique, and recommended judge as review inputs.

### Approve and import candidates

Import requires the stable IDs of at least one explicitly approved candidate:

```elixir
approved_case_ids =
  generation.cases
  |> Enum.filter(&approved_by_reviewer?/1)
  |> Enum.map(& &1.id)

{:ok, %{created: created, skipped: skipped}} =
  Aludel.RedTeam.import_generated(dataset, generation,
    approved_case_ids: approved_case_ids,
    variable: "input",
    judge_provider_id: generator_provider.id,
    judge_threshold: 80
  )
```

The judge provider defaults to the provider that generated the candidates. Each imported case receives its recommended built-in rubric judge. You can select another provider UUID and a threshold from 0 through 100.

Before locking the dataset, Aludel revalidates the complete generation checksum, its outcome accounting, and every candidate checksum. Candidate IDs must be non-empty, unique, and present in that generation. Approved cases retain generation status, failures, observed usage, applied limits, provider and model identity, target-context checksum, rationale, classification, review evidence, and import checksums in metadata. Raw target context is not copied into the entry.

The complete approved selection is written atomically in generation order. Repeating the same import returns the existing entries in `skipped`. A changed payload, generation receipt, review record, variable, or judge configuration under the same deduplication key returns `{:error, {:deduplication_conflict, key}}` and rolls back every new entry in that call.

Generation and approval/import are Elixir API features. The dashboard can inspect and edit imported entries and populate suites from their dataset, while `mix aludel.eval`, ExUnit, and the evaluation API run the resulting persisted suite. There is no separate generation or import command in the Mix CLI and no generation/import form in the dashboard.

## Use the entries

The catalog is exposed through the Elixir API. Its output is normal dataset data:

1. Inspect or edit the materialized dataset in the dashboard.
2. Populate a suite from the dataset in the dashboard or with `Aludel.Datasets.populate_suite/2`.
3. Run the suite in the dashboard, with `mix aludel.eval`, through ExUnit, or with `Aludel.Evals.execute_suite/4`.
4. Apply quality policies and reporters exactly as you would for any other suite.

There is no separate red-team CLI command or catalog browser in the dashboard in this release.
