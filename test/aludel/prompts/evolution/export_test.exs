defmodule Aludel.Prompts.Evolution.ExportTest do
  use Aludel.DataCase, async: true

  alias Aludel.Prompts.Evolution.Export
  alias Aludel.Prompts.Prompt
  alias Decimal

  describe "to_json/2" do
    test "serializes prompt and metrics to JSON structure" do
      prompt = %Prompt{
        id: "prompt-123",
        name: "Test Prompt",
        description: "A test prompt",
        tags: ["test", "example"]
      }

      created_at = ~U[2026-01-15 10:00:00Z]

      metrics = [
        %{
          version_id: "v1",
          version_number: 1,
          created_at: created_at,
          total_runs: 10,
          avg_pass_rate: 85.5,
          avg_score: Decimal.new("75.25"),
          avg_cost_usd: Decimal.new("0.0025"),
          avg_latency_ms: 250,
          provider_breakdown: [
            %{
              provider_id: "p1",
              provider_name: "Provider A",
              runs: 5,
              avg_pass_rate: 90.0,
              avg_score: Decimal.new("80.0"),
              avg_cost_usd: Decimal.new("0.0030"),
              avg_latency_ms: 200
            }
          ]
        }
      ]

      result = Export.to_json(prompt, metrics)

      assert result.type == "prompt_evolution"
      assert result.prompt.id == "prompt-123"
      assert result.prompt.name == "Test Prompt"
      assert result.prompt.description == "A test prompt"
      assert result.prompt.tags == ["test", "example"]

      assert length(result.metrics) == 1
      [metric] = result.metrics

      assert metric.version_id == "v1"
      assert metric.version_number == 1
      assert metric.created_at == "2026-01-15T10:00:00Z"
      assert metric.total_runs == 10
      assert metric.avg_pass_rate == 85.5
      assert metric.avg_score == 75.25
      assert metric.avg_cost_usd == 0.0025
      assert metric.avg_latency_ms == 250

      assert length(metric.provider_breakdown) == 1
      [breakdown] = metric.provider_breakdown

      assert breakdown.provider_id == "p1"
      assert breakdown.provider_name == "Provider A"
      assert breakdown.runs == 5
      assert breakdown.avg_pass_rate == 90.0
      assert breakdown.avg_score == 80.0
      assert breakdown.avg_cost_usd == 0.003
      assert breakdown.avg_latency_ms == 200
    end

    test "handles nil decimal values" do
      prompt = %Prompt{
        id: "prompt-123",
        name: "Test Prompt",
        description: nil,
        tags: []
      }

      metrics = [
        %{
          version_id: "v1",
          version_number: 1,
          created_at: ~U[2026-01-15 10:00:00Z],
          total_runs: 5,
          avg_pass_rate: 100.0,
          avg_score: nil,
          avg_cost_usd: nil,
          avg_latency_ms: nil,
          provider_breakdown: []
        }
      ]

      result = Export.to_json(prompt, metrics)

      [metric] = result.metrics
      assert metric.avg_score == nil
      assert metric.avg_cost_usd == nil
      assert metric.avg_latency_ms == nil
    end

    test "includes exported_at timestamp" do
      prompt = %Prompt{
        id: "prompt-123",
        name: "Test Prompt",
        description: nil,
        tags: []
      }

      result = Export.to_json(prompt, [])

      assert is_binary(result.exported_at)
      assert String.contains?(result.exported_at, "T")
      assert String.contains?(result.exported_at, "Z")
    end
  end

  describe "to_csv/1" do
    test "generates CSV with proper headers" do
      metrics = []

      csv = Export.to_csv(metrics)

      [header | _] = String.split(csv, "\n", trim: true)

      assert header ==
               "version,created_at,total_runs,avg_pass_rate,avg_score,avg_cost_usd,avg_latency_ms,provider_name,provider_runs,provider_pass_rate,provider_score,provider_cost_usd,provider_latency_ms"
    end

    test "formats floats with 4 decimal places" do
      metrics = [
        %{
          version_number: 1,
          created_at: ~U[2026-01-15 10:00:00Z],
          total_runs: 10,
          avg_pass_rate: 85.5,
          avg_score: Decimal.new("75.2567"),
          avg_cost_usd: Decimal.new("0.002"),
          avg_latency_ms: 250,
          provider_breakdown: [
            %{
              provider_name: "Provider A",
              runs: 5,
              avg_pass_rate: 90.125,
              avg_score: Decimal.new("80.999"),
              avg_cost_usd: Decimal.new("0.0030"),
              avg_latency_ms: 200
            }
          ]
        }
      ]

      csv = Export.to_csv(metrics)
      [_header, row] = String.split(csv, "\n", trim: true)

      assert row =~ "85.5000"
      assert row =~ "75.2567"
      assert row =~ "0.0020"
      assert row =~ "90.1250"
      assert row =~ "80.9990"
      assert row =~ "0.0030"
    end

    test "quotes string fields with CSV control characters" do
      metrics = [
        %{
          version_number: 1,
          created_at: ~U[2026-01-15 10:00:00Z],
          total_runs: 1,
          avg_pass_rate: 100.0,
          avg_score: Decimal.new("100.0"),
          avg_cost_usd: Decimal.new("0.001"),
          avg_latency_ms: 100,
          provider_breakdown: [
            %{
              provider_name: "Provider, \"North\"\nRegion",
              runs: 1,
              avg_pass_rate: 100.0,
              avg_score: Decimal.new("100.0"),
              avg_cost_usd: Decimal.new("0.001"),
              avg_latency_ms: 100
            }
          ]
        }
      ]

      csv = Export.to_csv(metrics)

      assert csv =~ "\"Provider, \"\"North\"\"\nRegion\""
    end

    test "neutralizes spreadsheet formulas in exported string fields" do
      metrics = [
        %{
          version_number: 1,
          created_at: ~U[2026-01-15 10:00:00Z],
          total_runs: 1,
          avg_pass_rate: 100.0,
          avg_score: Decimal.new("100.0"),
          avg_cost_usd: Decimal.new("0.001"),
          avg_latency_ms: 100,
          provider_breakdown: [
            %{
              provider_name: "=SUM(A1:A2)",
              runs: 1,
              avg_pass_rate: 100.0,
              avg_score: Decimal.new("100.0"),
              avg_cost_usd: Decimal.new("0.001"),
              avg_latency_ms: 100
            }
          ]
        }
      ]

      csv = Export.to_csv(metrics)

      assert csv =~ ",'=SUM(A1:A2),"
      refute csv =~ ",=SUM(A1:A2),"
    end

    test "generates one row per provider when breakdown exists" do
      metrics = [
        %{
          version_number: 1,
          created_at: ~U[2026-01-15 10:00:00Z],
          total_runs: 15,
          avg_pass_rate: 88.0,
          avg_score: Decimal.new("82.0"),
          avg_cost_usd: Decimal.new("0.0025"),
          avg_latency_ms: 300,
          provider_breakdown: [
            %{
              provider_name: "Provider A",
              runs: 10,
              avg_pass_rate: 90.0,
              avg_score: Decimal.new("85.0"),
              avg_cost_usd: Decimal.new("0.0020"),
              avg_latency_ms: 250
            },
            %{
              provider_name: "Provider B",
              runs: 5,
              avg_pass_rate: 80.0,
              avg_score: Decimal.new("75.0"),
              avg_cost_usd: Decimal.new("0.0035"),
              avg_latency_ms: 400
            }
          ]
        }
      ]

      csv = Export.to_csv(metrics)
      rows = String.split(csv, "\n", trim: true)

      assert length(rows) == 3
      [_header, row1, row2] = rows

      assert row1 =~ "Provider A"
      assert row2 =~ "Provider B"
    end

    test "generates single row with empty provider fields when no breakdown" do
      metrics = [
        %{
          version_number: 2,
          created_at: ~U[2026-01-16 10:00:00Z],
          total_runs: 5,
          avg_pass_rate: 100.0,
          avg_score: Decimal.new("95.0"),
          avg_cost_usd: Decimal.new("0.0015"),
          avg_latency_ms: 150,
          provider_breakdown: []
        }
      ]

      csv = Export.to_csv(metrics)
      [_header, row] = String.split(csv, "\n", trim: true)

      # Version and aggregate metrics should be present
      assert row =~ "2"
      assert row =~ "2026-01-16T10:00:00Z"
      assert row =~ "5"
      assert row =~ "100.0000"
      assert row =~ "95.0000"
      assert row =~ "0.0015"
      assert row =~ "150"

      # Provider fields should be empty (ending commas)
      assert String.ends_with?(row, ",,,,,,")
    end

    test "handles nil values in metrics" do
      metrics = [
        %{
          version_number: 1,
          created_at: nil,
          total_runs: 0,
          avg_pass_rate: nil,
          avg_score: nil,
          avg_cost_usd: nil,
          avg_latency_ms: nil,
          provider_breakdown: []
        }
      ]

      csv = Export.to_csv(metrics)
      [_header, row] = String.split(csv, "\n", trim: true)

      # Should have version and zeros, but empty strings for nil values
      assert row =~ "1"
      assert row =~ "0"
    end

    test "formats datetime as ISO8601" do
      metrics = [
        %{
          version_number: 1,
          created_at: ~U[2026-05-28 14:30:45Z],
          total_runs: 1,
          avg_pass_rate: 100.0,
          avg_score: Decimal.new("100.0"),
          avg_cost_usd: Decimal.new("0.001"),
          avg_latency_ms: 100,
          provider_breakdown: []
        }
      ]

      csv = Export.to_csv(metrics)
      [_header, row] = String.split(csv, "\n", trim: true)

      assert row =~ "2026-05-28T14:30:45Z"
    end
  end
end
