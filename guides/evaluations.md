# Evaluation Guide

This guide builds a repeatable evaluation loop with prompts, datasets, suites, assertions, retries, exports, and CI.

## 1. Create a prompt

Create a prompt in **Prompts → New Prompt**:

```text
Return a JSON object with a short answer and confidence from 0 to 1.

Question: {{question}}
```

Aludel extracts `question` as a required variable. Editing the template later creates a new immutable version, so old suite runs remain tied to the exact template they evaluated.

## 2. Compare providers

Open the prompt and choose **Run**. Enter a value for `question`, select one or more providers, and start the run.

The results update as each provider completes. Compare output, tokens, latency, and cost side by side. A failed provider does not discard successful sibling results; the run records a partial failure.

Use **Copy output** for a quick handoff or **Export JSON** when you need provider identity, timing, callback metadata, or normalized execution artifacts.

## 3. Create a reusable dataset

Open **Datasets**, create a dataset, and add an entry with variables:

```json
{
  "question": "Which planet is known as the Red Planet?"
}
```

For a multi-turn example, use messages instead:

```json
[
  {"role": "user", "content": "Remember that my preferred unit is Celsius."},
  {"role": "assistant", "content": "Understood."},
  {"role": "user", "content": "What unit should you use in the forecast?"}
]
```

An entry must contain variables, messages, or both. Add JSON metadata such as `{"language":"en","priority":"smoke"}` to filter entries later.

## 4. Define assertions

Assertions can be edited visually or as JSON.

### Contains and excludes

```json
[
  {"type": "contains", "value": "Mars"},
  {"type": "not_contains", "value": "Jupiter"}
]
```

### Regular expression and exact match

```json
[
  {"type": "regex", "value": "(?i)confidence"},
  {"type": "exact_match", "value": "Mars"}
]
```

`regex` fails cleanly when the pattern is invalid. `exact_match` compares the entire output without trimming or normalization.

### Typed JSON field

```json
[
  {"type": "json_field", "field": "answer", "expected": "Mars"},
  {"type": "json_field", "field": "confidence", "expected": 1}
]
```

Dot-separated paths access nested fields. Expected values remain typed, so JSON number `1`, string `"1"`, and boolean `true` are distinct.

### Scored deep JSON comparison

```json
[
  {
    "type": "json_deep_compare",
    "expected": {
      "answer": "Mars",
      "evidence": {"category": "astronomy"}
    },
    "threshold": 75.0
  }
]
```

Deep comparison scores the expected JSON structure field by field. Extra fields in the model output do not reduce the score. The assertion passes when the match score meets the threshold; the default threshold is 100%.

JSON metrics also accept model output wrapped in a Markdown JSON code fence.

### Custom rubric judge

Use a rubric judge when correctness depends on meaning rather than an exact string or JSON shape. The judge provider is separate from the provider being evaluated, and its usage, cost, latency, model, score, and reasoning are recorded with the assertion result.

```json
[
  {
    "type": "rubric_judge",
    "rubric": "The answer must be factually correct, directly answer the question, and avoid unsupported claims.",
    "provider_id": "00000000-0000-0000-0000-000000000000",
    "threshold": 80,
    "expected": "Optional reference answer",
    "context": "Optional grounding context"
  }
]
```

Author rubric assertions in the JSON assertion editor. Scores range from 0 to 100, and Aludel derives the pass or fail result from `threshold`; a model-provided verdict is never trusted. Evaluation evidence is bounded and sent as untrusted JSON data so content under test cannot replace the rubric or output contract.

For common checks, replace `rubric` with a versioned built-in `template`:

```json
[
  {
    "type": "rubric_judge",
    "template": "faithfulness",
    "provider_id": "00000000-0000-0000-0000-000000000000",
    "threshold": 85
  }
]
```

| Template | Use it to evaluate |
|---|---|
| `correctness` | Agreement with the expected answer and supplied evidence |
| `relevance` | Whether the response directly addresses the requested task |
| `faithfulness` | Whether claims are supported by grounding context or documents |
| `safety` | Harmful, dangerous, or policy-violating assistance |
| `refusal` | Whether a refusal is appropriate, clear, and useful |
| `pii` | Disclosure or inference of sensitive personal information |
| `hallucination` | Fabricated facts, citations, entities, tool results, or outcomes |

Templates and custom rubrics are mutually exclusive. Aludel records the resolved rubric and template version with each result, so a historical run retains the criteria it used.

### Inspect metric context and evaluator details

Suite execution gives every metric a normalized `Aludel.Evals.Metric.Context` containing the generated output, rendered input, prompt template, variables, messages, documents, metadata, provider, prompt version, and execution details. Expected references remain in assertion configuration. Direct callers can also set `expected` on the context.

Direct callers can use the same contract:

```elixir
alias Aludel.Evals.AssertionEvaluator
alias Aludel.Evals.Metric.Context

context =
  Context.new("Paris",
    expected: "Paris",
    rendered_input: "What is the capital of France?",
    variables: %{"country" => "France"},
    metadata: %{"category" => "geography"}
  )

result =
  AssertionEvaluator.evaluate(context, %{
    "type" => "contains",
    "value" => "Paris"
  })
```

Passing a string as the first argument remains supported for metrics that only need generated text.

Every assertion result has an `evaluator` map. Deterministic metrics record `status: "completed"` and measured `duration_ms`. Model-backed judges also record their provider, model, input and output tokens, and cost independently from the model being evaluated.

Evaluator status is one of `completed`, `error`, or `unavailable`. Failures use stable structured error types without retaining exception messages, provider response bodies, credentials, or other sensitive details. This keeps a failed evaluator distinct from an assertion that ran successfully and scored the output as failing.

### Repeat nondeterministic cases

Run each test case more than once when a single model response is not reliable enough to make a decision:

```elixir
{:ok, suite_run} =
  Aludel.Evals.execute_suite(suite, prompt_version, provider,
    samples: 5,
    reducer: :majority
  )
```

`samples` accepts `1` through `20`. Reducers can require `:all`, `:any`, a strict `:majority`, or a minimum rate such as `{:minimum_pass_rate, 0.8}`. Invalid sampling configuration returns an error before any model request is made.

Sampled results retain every ordered attempt and record passed and failed counts, pass rate, reducer configuration, and the representative attempt. Token usage, cost, and latency are summed across attempts; available scores are averaged. Retrying a sampled test case reruns the complete persisted sampling configuration and replaces the previous aggregate.

### Enforce a versioned quality policy

Create an immutable policy version for a suite:

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
      %{
        "id" => "faithfulness",
        "type" => "evaluator_score",
        "metric" => "rubric_judge",
        "minimum" => 85
      },
      %{"id" => "cost", "type" => "total_cost_usd", "maximum" => 0.50},
      %{"id" => "latency", "type" => "average_latency_ms", "maximum" => 1_500}
    ]
  })
```

Pass-rate minimums use values from `0.0` through `1.0`; evaluator-score minimums use `0` through `100`. Metadata groups match test cases whose metadata contains every configured key and value. Evaluator-score rules average every completed matching assertion, including every retained sampling attempt. Cost uses the full suite-run total, while latency uses the average across available request samples.

Creating another policy produces the next suite-local version. Suite execution snapshots the latest version before making model requests. A later single-case retry restores the policy associated with the original run instead of switching to a newer contract.

Each rule and the aggregate policy record a status. `passed` and `failed` are measured quality decisions. `unavailable` means required evidence such as a matching metadata group, completed evaluator score, cost, or latency was missing. `invalid` means a direct policy evaluation received a malformed or unsupported definition. Stored policy versions are field-strict, JSON-only, limited to 50 rules and 100,000 encoded bytes, and validated before persistence.

```elixir
case suite_run.quality_policy_result do
  %{"status" => "passed"} -> :ok
  %{"status" => status, "rules" => rules} -> {:error, status, rules}
  nil -> :no_policy
end
```

`mix aludel.eval` uses a stored policy outcome as its process exit gate. Suites without a policy keep the legacy behavior: every test case must pass and an empty suite fails.

## 5. Populate a suite

Create an evaluation suite for the prompt, open it, select a dataset, and choose **Add entries**. Aludel copies entries in dataset order and records each source entry.

Repopulating from the same dataset skips entries already imported into that suite. Later edits to a suite test case do not mutate the source dataset.

You can also add cases manually or import them from a file.

### CSV import

```csv
input,expected,assertion,notes
"Which planet is red?","Mars","contains","smoke test"
"Name Earth's moon","Moon","exact_match","basic fact"
```

### JSON import

```json
[
  {"input": "Which planet is red?", "expected": "Mars", "assertion": "contains"},
  {"input": "Name Earth's moon", "expected": "Moon", "assertion": "exact_match"}
]
```

File imports currently support `contains`, `not_contains`, `regex`, and `exact_match`. The preview reports accepted and rejected rows before anything is persisted. Use the suite editor for structured JSON assertions and multi-turn messages.

## 6. Attach documents

Attach PDF, PNG, JPEG, JSON, CSV, or plain-text files while creating or editing a suite test case. The selected storage adapter persists the bytes, and execution loads them only when the case runs.

Use this for extraction, classification, document QA, or image-aware prompts. If a provider does not accept PDFs natively, configure the ImageMagick converter described in the [Embedding Guide](embedding.md).

## 7. Run and inspect a suite

Choose a prompt version and provider, then start the suite. Each result includes output, assertion details, score, tokens, cost, latency, metadata, and execution artifacts when available.

If one test case needs another attempt, use its retry action. Aludel updates that result, recalculates suite aggregates, and records retry count and time without rerunning successful cases.

## 8. Compare prompt versions

Open the prompt's **Evolution** page to compare overall or provider-specific pass rate, score, cost, and latency. Select a suite to calculate a Pareto frontier for that exact workload.

Use the version delta and signal badges to spot improvements, regressions, unstable pass rates, or insufficient evidence. Export evolution data as JSON or CSV for external analysis.

When failed suite evidence exists, choose a provider and generate a failure reflection. Review the proposed template and rationale, then either dismiss it or accept it as a new prompt version.

## 9. Add a CI quality gate

Run the same suite headlessly:

```bash
mix aludel.eval \
  --suite-id SUITE_ID \
  --prompt-version-id PROMPT_VERSION_ID \
  --provider-id PROVIDER_ID
```

The command emits one schema-version-2 JSON object by default:

```json
{
  "type": "aludel_eval",
  "schema_version": 2,
  "status": "passed",
  "suite_id": "SUITE_ID",
  "prompt_version_id": "PROMPT_VERSION_ID",
  "provider_id": "PROVIDER_ID",
  "summary": {
    "passed": 2,
    "failed": 0,
    "total": 2,
    "pass_rate": 100.0,
    "avg_score": "100.0"
  }
}
```

The task exits unsuccessfully when arguments or targets are invalid, the prompt version belongs to another prompt, execution cannot be persisted, the suite is empty, or the active quality gate does not pass.

Choose `--format console`, `--format junit`, or `--format github` for a human-readable log, CI test report, or GitHub Actions annotations. Add `--output PATH` to write the report to a file, `--pretty` to pretty-print JSON, or JUnit-only `--include-output` when the artifact is appropriate for generated responses. See the [reporter guide](reporters.html) for complete examples and the custom reporter behavior.
