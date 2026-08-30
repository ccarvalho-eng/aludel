defmodule Aludel.Runs.RunResultTest do
  use Aludel.DataCase

  alias Aludel.Runs.RunResult

  import Aludel.PromptsFixtures
  import Aludel.ProvidersFixtures

  describe "changeset/2" do
    setup do
      prompt = prompt_fixture()

      {:ok, version} =
        Aludel.Prompts.create_prompt_version(prompt, "Hello {{user}}")

      {:ok, run} =
        Aludel.Runs.create_run(%{
          prompt_version_id: version.id,
          variable_values: %{"user" => "Test"}
        })

      provider = provider_fixture()
      {:ok, run: run, provider: provider}
    end

    test "valid changeset with all required fields", %{
      run: run,
      provider: provider
    } do
      changeset =
        RunResult.changeset(%RunResult{}, %{
          run_id: run.id,
          provider_id: provider.id,
          output: "Hello world",
          input_tokens: 10,
          output_tokens: 5,
          latency_ms: 500,
          cost_usd: 0.001,
          status: :completed
        })

      assert changeset.valid?
    end

    test "valid changeset with pending status", %{
      run: run,
      provider: provider
    } do
      changeset =
        RunResult.changeset(%RunResult{}, %{
          run_id: run.id,
          provider_id: provider.id,
          output: "",
          input_tokens: 0,
          output_tokens: 0,
          latency_ms: 0,
          cost_usd: 0.0,
          status: :pending
        })

      assert changeset.valid?
    end

    test "valid changeset with running status", %{
      run: run,
      provider: provider
    } do
      changeset =
        RunResult.changeset(%RunResult{}, %{
          run_id: run.id,
          provider_id: provider.id,
          output: "Partial",
          input_tokens: 10,
          output_tokens: 2,
          latency_ms: 200,
          cost_usd: 0.0005,
          status: :running,
          started_at: ~U[2026-04-20 12:00:00Z]
        })

      assert changeset.valid?
      assert changeset.changes.started_at == ~U[2026-04-20 12:00:00Z]
    end

    test "valid changeset with error status and error message", %{
      run: run,
      provider: provider
    } do
      changeset =
        RunResult.changeset(%RunResult{}, %{
          run_id: run.id,
          provider_id: provider.id,
          output: "",
          input_tokens: 10,
          output_tokens: 0,
          latency_ms: 500,
          cost_usd: 0.0,
          status: :error,
          error: "API request failed"
        })

      assert changeset.valid?
      assert changeset.changes.error == "API request failed"
    end

    test "invalid changeset without run_id", %{provider: provider} do
      changeset =
        RunResult.changeset(%RunResult{}, %{
          provider_id: provider.id,
          output: "Test",
          input_tokens: 10,
          output_tokens: 5,
          latency_ms: 500,
          cost_usd: 0.001,
          status: :completed
        })

      refute changeset.valid?
      assert %{run_id: _} = errors_on(changeset)
    end

    test "invalid changeset without provider_id", %{run: run} do
      changeset =
        RunResult.changeset(%RunResult{}, %{
          run_id: run.id,
          output: "Test",
          input_tokens: 10,
          output_tokens: 5,
          latency_ms: 500,
          cost_usd: 0.001,
          status: :completed
        })

      refute changeset.valid?
      assert %{provider_id: _} = errors_on(changeset)
    end

    test "invalid changeset without status", %{run: run, provider: provider} do
      changeset =
        RunResult.changeset(%RunResult{}, %{
          run_id: run.id,
          provider_id: provider.id,
          output: "Test",
          input_tokens: 10,
          output_tokens: 5,
          latency_ms: 500,
          cost_usd: 0.001
        })

      refute changeset.valid?
      assert %{status: _} = errors_on(changeset)
    end

    test "invalid changeset with invalid status", %{
      run: run,
      provider: provider
    } do
      changeset =
        RunResult.changeset(%RunResult{}, %{
          run_id: run.id,
          provider_id: provider.id,
          output: "Test",
          input_tokens: 10,
          output_tokens: 5,
          latency_ms: 500,
          cost_usd: 0.001,
          status: :invalid_status
        })

      refute changeset.valid?
      assert %{status: _} = errors_on(changeset)
    end

    test "error field is optional", %{run: run, provider: provider} do
      changeset =
        RunResult.changeset(%RunResult{}, %{
          run_id: run.id,
          provider_id: provider.id,
          output: "Test",
          input_tokens: 10,
          output_tokens: 5,
          latency_ms: 500,
          cost_usd: 0.001,
          status: :completed
        })

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :error)
    end

    test "accepts callback metadata", %{run: run, provider: provider} do
      metadata = %{"trace_id" => "trace-123", "host" => "embedded-app"}

      changeset =
        RunResult.changeset(%RunResult{}, %{
          run_id: run.id,
          provider_id: provider.id,
          output: "Hello world",
          status: :completed,
          metadata: metadata
        })

      assert changeset.valid?
      assert changeset.changes.metadata == metadata
    end

    test "accepts versioned execution artifacts", %{run: run, provider: provider} do
      artifacts = %{
        "schema_version" => 1,
        "steps" => [%{"index" => 0, "mode" => "native", "status" => "completed"}]
      }

      changeset =
        RunResult.changeset(%RunResult{}, %{
          run_id: run.id,
          provider_id: provider.id,
          output: "Hello world",
          status: :completed,
          artifacts: artifacts
        })

      assert changeset.valid?
      assert changeset.changes.artifacts == artifacts
    end

    test "rejects artifacts that cannot be encoded as JSON", %{run: run, provider: provider} do
      changeset =
        RunResult.changeset(%RunResult{}, %{
          run_id: run.id,
          provider_id: provider.id,
          status: :completed,
          artifacts: %{"pid" => self()}
        })

      refute changeset.valid?
      assert %{artifacts: ["must be JSON-encodable"]} = errors_on(changeset)
    end

    test "rejects metadata that cannot be encoded as JSON", %{run: run, provider: provider} do
      changeset =
        RunResult.changeset(%RunResult{}, %{
          run_id: run.id,
          provider_id: provider.id,
          output: "Hello world",
          status: :completed,
          metadata: %{"pid" => self()}
        })

      refute changeset.valid?
      assert %{metadata: ["must be JSON-encodable"]} = errors_on(changeset)
    end
  end
end
