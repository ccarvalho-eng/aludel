# ExUnit Evaluations

`Aludel.ExUnit` lets application tests use the same metrics, persisted suite results, and versioned quality policies as the Aludel workbench and headless Mix task. Add `use Aludel.ExUnit` to import the helpers, or call them through the module directly.

## Assert one generated response

`assert_evaluation/2` accepts generated output and one assertion map:

```elixir
defmodule MyApp.AnswerTest do
  use ExUnit.Case
  use Aludel.ExUnit

  test "returns the canonical city" do
    output = MyApp.answer("What is the capital of France?")

    result =
      assert_evaluation(output, %{
        "type" => "exact_match",
        "value" => "Paris"
      })

    assert result["score"] == 100.0
  end
end
```

The helper returns the normalized assertion result when it passes. A failed, invalid, unsupported, or unavailable evaluator raises `ExUnit.AssertionError`.

All built-in metrics are available: `contains`, `not_contains`, resource-bounded `regex`, `exact_match`, `json_field`, `json_deep_compare`, and `rubric_judge`. Regex limit failures use the same assertion failure path and do not expose generated output in evaluator error details. Model-based judge assertions use their configured Aludel provider and retain separate evaluator evidence.

## Assert several metrics

`assert_evaluations/2` runs every assertion against the same response and returns results in authoring order:

```elixir
results =
  assert_evaluations(output, [
    %{"type" => "contains", "value" => "reset link"},
    %{"type" => "not_contains", "value" => "share your password"},
    %{"type" => "regex", "value" => "(?i)expires? in 15 minutes"}
  ])

assert Enum.all?(results, & &1["passed"])
```

An empty assertion list fails instead of passing vacuously. When several assertions fail, one error lists each non-passing metric up to a bounded diagnostic limit.

## Supply metric context

Pass `Aludel.Evals.Metric.Context` when a custom metric or rubric judge needs input, expected output, documents, messages, metadata, or execution evidence:

```elixir
alias Aludel.Evals.Metric.Context

context =
  Context.new(output,
    expected: "Paris",
    rendered_input: "What is the capital of France?",
    metadata: %{"category" => "geography"}
  )

assert_evaluation(context, %{
  "type" => "contains",
  "value" => "Paris"
})
```

## Gate an existing suite run

`assert_suite_run/1` applies the normalized report status to an existing `Aludel.Evals.SuiteRun`:

```elixir
suite_run = Aludel.Evals.get_suite_run!(run_id)

assert_suite_run(suite_run)
```

When the run has a stored quality-policy result, its `passed`, `failed`, `invalid`, or `unavailable` status is authoritative. Without a policy, every case must pass and the suite must contain at least one result. The unchanged suite-run struct is returned on success.

## Execute, persist, and gate a suite

`assert_suite/3` runs with default sampling. `assert_suite/4` accepts sampling options. Both run the provider-backed evaluation through `Aludel.Evals.execute_suite/4`, persist the result, and then apply `assert_suite_run/1`:

```elixir
suite = Aludel.Evals.get_suite!(suite_id)
prompt_version = Aludel.Prompts.get_prompt_version!(prompt_version_id)
provider = Aludel.Providers.get_provider!(provider_id)

suite_run =
  assert_suite(suite, prompt_version, provider,
    samples: 5,
    reducer: :majority
  )

assert suite_run.passed >= 1
```

A completed non-passing run stays persisted before the assertion is raised, preserving the evidence for the dashboard and later comparison. The prompt version must belong to the suite's prompt. Pre-execution errors such as a prompt mismatch or invalid sampling configuration fail with a stable category and do not create a suite run.

## Failure messages and sensitive output

Failures identify the metric type, evaluator status, score, failed case IDs, and non-passing policy rules. Diagnostic text is bounded and control characters are normalized. Generated model output and expected values are not copied into the assertion message, keeping ordinary test and CI logs smaller and reducing accidental disclosure.

Inspect the returned or persisted result explicitly when a trusted local workflow needs the complete output.

## Database and provider setup

Inline deterministic assertions do not need a database or running Aludel application. Rubric judges and the `assert_suite` helpers use configured providers; suite execution also uses the configured Aludel repository.

In a Phoenix application, keep normal Ecto SQL sandbox ownership around tests that execute or load persisted suites. Provider adapters should be replaced only at their documented application boundary in tests. Avoid global mocks in asynchronous cases, and choose normal ExUnit timeouts that cover the bounded provider requests and sampling count used by the suite.
