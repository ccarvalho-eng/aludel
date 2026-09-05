# Evaluation Reporters

Aludel turns every persisted suite run into one normalized report before formatting it. This gives local tools and CI systems the same status, identifiers, summaries, quality-policy evidence, and case results without tying an output format to the database schema.

## Preview and download reports in the dashboard

Open a suite, find a completed result, and choose **Reports**. Select console text, JSON v2, JUnit XML, or GitHub annotations to update the preview and download the complete rendered report. Previews are limited to 100,000 characters so a large result cannot overwhelm the page; the downloaded report is not truncated and uses no-store response headers.

Console and GitHub formats omit generated responses. JSON includes them in its stable result schema. JUnit omits them until **Include generated output** is enabled, and keeps the choice in the download URL so preview and file content match. The full persisted suite-run JSON export remains available separately from the normalized report.

## Render reports in Elixir

Pass a persisted `Aludel.Evals.SuiteRun` or an existing `Aludel.Evals.Report` to `Aludel.Evals.Reporter`:

```elixir
alias Aludel.Evals.Reporter

{:ok, console} = Reporter.render(suite_run, :console)
{:ok, json} = Reporter.render(suite_run, :json, pretty: true)
{:ok, junit_xml} = Reporter.render(suite_run, :junit)
{:ok, annotations} = Reporter.render(suite_run, :github)
```

Use `render!/3` when an unsupported reporter or invalid custom result should raise `ArgumentError`.

## Console

The console reporter prints a compact, ANSI-free summary with one line per test case and policy-rule evidence when present:

```text
Aludel evaluation FAILED
Suite run: 017f...
Summary: 2 passed, 1 failed, 66.67% pass rate
Averages: score=86.7, cost=0.0041 USD, latency=428 ms
[PASS] test case 018a...
[FAIL] test case 018b...
Policy: failed
  [FAILED] priority: Pass rate was below the configured minimum
```

Generated model output is omitted from console text so routine logs remain concise.

## JSON schema version 2

The JSON reporter serializes `Aludel.Evals.Report.to_map/1`. Its top-level contract is:

```json
{
  "type": "aludel_eval",
  "schema_version": 2,
  "status": "passed",
  "suite_run_id": "RUN_ID",
  "suite_id": "SUITE_ID",
  "prompt_version_id": "PROMPT_VERSION_ID",
  "provider_id": "PROVIDER_ID",
  "quality_policy": null,
  "summary": {
    "passed": 2,
    "failed": 0,
    "total": 2,
    "pass_rate": 100.0,
    "avg_score": "100.0",
    "avg_cost_usd": "0.0025",
    "avg_latency_ms": 320,
    "total_cost_usd": "0.005",
    "cost_sample_count": 2,
    "total_latency_ms": 640,
    "latency_sample_count": 2
  },
  "results": []
}
```

Decimal values remain decimal strings, preventing an interchange consumer from silently losing precision. JSON object key order is not part of the contract.

## JUnit XML

The JUnit reporter maps each evaluation case to `<testcase>` and failed assertions to `<failure>`. Generated output is omitted by default. A quality policy that rejects otherwise passing cases becomes an additional failed `quality-policy` case. An empty run becomes a failed `evaluation` case. These synthetic cases keep CI test viewers from reporting a false success.

```elixir
xml = Reporter.render!(suite_run, :junit)
File.write!("aludel-junit.xml", xml)
```

Identifiers and failure reasons are escaped as XML text. XML 1.0 control characters are removed. Add `include_output: true` to `Reporter.render!/3`, or `--include-output` to the Mix task, only when the destination artifact is appropriate for generated responses; enabled output is escaped inside `<system-out>`.

## GitHub Actions annotations

The GitHub reporter emits an error annotation for each failed case and non-passing policy rule. A passing report emits one notice:

```yaml
- name: Run LLM evaluation gate
  run: >-
    mix aludel.eval
    --suite-id "$SUITE_ID"
    --prompt-version-id "$PROMPT_VERSION_ID"
    --provider-id "$PROVIDER_ID"
    --format github
```

Annotation titles and messages escape workflow-command control characters. Messages are bounded before rendering so evaluator output cannot inject a second command or create an unbounded annotation.

## Mix task output

JSON is the default format:

```bash
mix aludel.eval \
  --suite-id SUITE_ID \
  --prompt-version-id PROMPT_VERSION_ID \
  --provider-id PROVIDER_ID \
  --pretty
```

Write JUnit XML to a CI artifact path:

```bash
mix aludel.eval \
  --suite-id SUITE_ID \
  --prompt-version-id PROMPT_VERSION_ID \
  --provider-id PROVIDER_ID \
  --format junit \
  --output aludel-junit.xml
```

The task writes the report before returning a nonzero exit for a failed, unavailable, or invalid quality decision. Argument and execution errors remain machine-readable JSON error envelopes.

## Custom reporters

A custom reporter receives the normalized report and keyword options, then returns `{:ok, iodata}` or `{:error, reason}`:

```elixir
defmodule MyApp.MarkdownReporter do
  @behaviour Aludel.Evals.Reporter

  alias Aludel.Evals.Report

  @impl true
  def render(%Report{} = report, _options) do
    {:ok, ["# Evaluation ", String.upcase(report.status), "\n"]}
  end
end

markdown =
  Aludel.Evals.Reporter.render!(
    suite_run,
    MyApp.MarkdownReporter
  )
```

Custom reporters should treat case output, assertion reasons, metadata, and identifiers as untrusted data and escape them for their target format.
