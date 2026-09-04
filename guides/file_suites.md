# File-Based Evaluation Suites

Versioned suite manifests make a persisted Aludel evaluation reproducible from a repository, script, or CI job. A manifest selects the suite, prompt version, provider, and optional repeated-sampling policy. The database remains authoritative for test cases, document associations, dataset provenance, and quality policies.

## YAML manifest

Create `evals/support-answer.yaml`:

```yaml
schema_version: 1
suite_id: 9a756a58-eaec-43ca-99e6-f5c016d85d0c
prompt_version_id: e74cf2e1-94b6-4bcb-9ed9-b259661be906
provider_id: e1c60ec0-6d55-419b-b958-7d088055254f
sampling:
  samples: 5
  reducer: majority
```

Replace the example UUIDs with IDs from your Aludel installation, then run:

```bash
mix aludel.eval --file evals/support-answer.yaml
```

`.yaml` and `.yml` extensions are supported.

## JSON manifest

JSON uses the same schema:

```json
{
  "schema_version": 1,
  "suite_id": "9a756a58-eaec-43ca-99e6-f5c016d85d0c",
  "prompt_version_id": "e74cf2e1-94b6-4bcb-9ed9-b259661be906",
  "provider_id": "e1c60ec0-6d55-419b-b958-7d088055254f",
  "sampling": {
    "samples": 5,
    "reducer": "minimum_pass_rate",
    "minimum_pass_rate": 0.8
  }
}
```

Run it the same way:

```bash
mix aludel.eval --file evals/support-answer.json
```

## Sampling options

`sampling` is optional. Without it, each test case runs once and must pass.

| Reducer | Meaning | Additional field |
|---|---|---|
| `all` | Every attempt must pass | None |
| `any` | At least one attempt must pass | None |
| `majority` | More than half of the attempts must pass | None |
| `minimum_pass_rate` | The pass rate must meet a chosen threshold | `minimum_pass_rate`, from `0.0` through `1.0` |

`samples` accepts integers from 1 through 20. The limit prevents an accidental manifest change from creating unbounded provider traffic.

For example, require four of five attempts to pass:

```yaml
sampling:
  samples: 5
  reducer: minimum_pass_rate
  minimum_pass_rate: 0.8
```

## Reports and quality gates

Reporter flags stay on the command line, so the same manifest can serve local output and different CI systems:

```bash
mix aludel.eval \
  --file evals/support-answer.yaml \
  --format junit \
  --output aludel-junit.xml
```

```bash
mix aludel.eval \
  --file evals/support-answer.yaml \
  --format github
```

The task exits unsuccessfully when the manifest or target records are invalid, execution fails, the suite is empty, or the effective quality decision does not pass. The suite's latest immutable quality policy is snapshotted at execution time. Without a policy, every persisted test case must pass.

`--file` is mutually exclusive with `--suite-id`, `--prompt-version-id`, and `--provider-id`. Report flags such as `--format`, `--output`, `--pretty`, and `--include-output` work with either target style.

## Load and execute in Elixir

Use `Aludel.Evals.FileSuite` from releases, scripts, or application code:

```elixir
alias Aludel.Evals.FileSuite

with {:ok, file_suite} <- FileSuite.load("evals/support-answer.yaml"),
     {:ok, suite_run} <- FileSuite.execute(file_suite) do
  {:ok, suite_run}
end
```

For the common one-step form:

```elixir
{:ok, suite_run} =
  Aludel.Evals.FileSuite.load_and_execute("evals/support-answer.json")
```

In-memory callers can use `load_string/2` with `:json` or `:yaml` before calling `execute/1`.

## Validation and ownership

Manifest validation happens before database lookup or model execution. Aludel rejects:

- files larger than 256 KiB or content that is not valid UTF-8
- extensions other than `.json`, `.yaml`, and `.yml`
- malformed content, duplicate mapping keys, YAML aliases, explicit YAML tags, and multiple YAML documents
- missing or unknown fields and unsupported schema versions
- non-UUID target identifiers
- invalid sample counts, reducers, or minimum pass rates
- prompt versions that do not belong to the suite's prompt

Errors return a stable map with `code` and `message` fields. The Mix task wraps that error in its schema-version-2 JSON error envelope.

A manifest deliberately does not contain test cases, provider credentials, output paths, or quality-policy definitions. Editing or executing one cannot repopulate a suite or alter its dataset links. Manage those records in Aludel, then commit only their stable identifiers and execution settings.

## CI example

```yaml
- name: Run evaluation gate
  run: mix aludel.eval --file evals/support-answer.yaml --format github
```

Provider configuration and credentials should come from the application's normal runtime configuration. Do not commit secrets to a suite manifest.
