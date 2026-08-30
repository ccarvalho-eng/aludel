defmodule Aludel.Prompts.EvolutionTest do
  use Aludel.DataCase, async: true

  import Aludel.PromptsFixtures
  import Aludel.ProvidersFixtures
  import Aludel.EvalsFixtures

  alias Aludel.Evals
  alias Aludel.Prompts
  alias Aludel.Prompts.Evolution

  describe "get_metrics/1" do
    test "returns empty list when prompt has no versions" do
      prompt = prompt_fixture()
      assert Evolution.get_metrics(prompt.id) == []
    end

    test "returns metrics for version with no suite runs" do
      prompt = prompt_fixture()
      {:ok, version} = Prompts.create_prompt_version(prompt, "Test {{var}}")

      metrics = Evolution.get_metrics(prompt.id)

      assert length(metrics) == 1
      assert [metric] = metrics
      assert metric.version_id == version.id
      assert metric.version_number == 1
      assert metric.total_runs == 0
      assert metric.avg_pass_rate == nil
      assert metric.avg_cost_usd == nil
      assert metric.avg_latency_ms == nil
      assert metric.avg_score == nil
      assert metric.provider_breakdown == []
    end

    test "calculates metrics for single version with suite runs" do
      prompt = prompt_fixture()
      provider = provider_fixture()
      {:ok, version} = Prompts.create_prompt_version(prompt, "Test {{var}}")
      suite = suite_fixture(%{prompt_id: prompt.id})

      # Create suite runs with varying pass rates
      {:ok, _sr1} =
        Evals.create_suite_run(%{
          suite_id: suite.id,
          prompt_version_id: version.id,
          provider_id: provider.id,
          passed: 8,
          failed: 2,
          avg_score: Decimal.new("72.5")
        })

      {:ok, _sr2} =
        Evals.create_suite_run(%{
          suite_id: suite.id,
          prompt_version_id: version.id,
          provider_id: provider.id,
          passed: 9,
          failed: 1,
          avg_score: Decimal.new("87.5")
        })

      metrics = Evolution.get_metrics(prompt.id)

      assert length(metrics) == 1
      assert [metric] = metrics
      assert metric.version_number == 1
      assert metric.total_runs == 2
      # (8+9) / (10+10) * 100 = 85.0
      assert metric.avg_pass_rate == 85.0
      assert Decimal.equal?(metric.avg_score, Decimal.new("80.0"))
      assert length(metric.provider_breakdown) == 1

      [breakdown] = metric.provider_breakdown
      assert breakdown.provider_id == provider.id
      assert breakdown.runs == 2
      assert breakdown.avg_pass_rate == 85.0
      assert Decimal.equal?(breakdown.avg_score, Decimal.new("80.0"))
    end

    test "tracks metrics across multiple versions" do
      prompt = prompt_fixture()
      provider = provider_fixture()
      {:ok, v1} = Prompts.create_prompt_version(prompt, "Version 1 {{var}}")
      {:ok, v2} = Prompts.create_prompt_version(prompt, "Version 2 {{var}}")
      suite = suite_fixture(%{prompt_id: prompt.id})

      # V1 with lower pass rate
      {:ok, _sr1} =
        Evals.create_suite_run(%{
          suite_id: suite.id,
          prompt_version_id: v1.id,
          provider_id: provider.id,
          passed: 6,
          failed: 4
        })

      # V2 with higher pass rate
      {:ok, _sr2} =
        Evals.create_suite_run(%{
          suite_id: suite.id,
          prompt_version_id: v2.id,
          provider_id: provider.id,
          passed: 9,
          failed: 1
        })

      metrics = Evolution.get_metrics(prompt.id)

      assert length(metrics) == 2
      assert [m1, m2] = metrics

      # Verify ordering by version number
      assert m1.version_number == 1
      assert m2.version_number == 2

      # Verify pass rates show improvement
      assert m1.avg_pass_rate == 60.0
      assert m2.avg_pass_rate == 90.0
    end

    test "calculates provider breakdown for multiple providers" do
      prompt = prompt_fixture()
      p1 = provider_fixture(%{name: "Provider A"})
      p2 = provider_fixture(%{name: "Provider B"})
      {:ok, version} = Prompts.create_prompt_version(prompt, "Test {{var}}")
      suite = suite_fixture(%{prompt_id: prompt.id})

      # Provider A: 80% pass rate
      {:ok, _sr1} =
        Evals.create_suite_run(%{
          suite_id: suite.id,
          prompt_version_id: version.id,
          provider_id: p1.id,
          passed: 8,
          failed: 2
        })

      # Provider B: 90% pass rate
      {:ok, _sr2} =
        Evals.create_suite_run(%{
          suite_id: suite.id,
          prompt_version_id: version.id,
          provider_id: p2.id,
          passed: 9,
          failed: 1
        })

      metrics = Evolution.get_metrics(prompt.id)
      assert [metric] = metrics

      assert length(metric.provider_breakdown) == 2
      assert [b1, b2] = metric.provider_breakdown

      # Sorted by provider name
      assert b1.provider_name == "Provider A"
      assert b1.avg_pass_rate == 80.0
      assert b2.provider_name == "Provider B"
      assert b2.avg_pass_rate == 90.0
    end

    test "handles suite runs with zero tests" do
      prompt = prompt_fixture()
      provider = provider_fixture()
      {:ok, version} = Prompts.create_prompt_version(prompt, "Test {{var}}")
      suite = suite_fixture(%{prompt_id: prompt.id})

      {:ok, _sr} =
        Evals.create_suite_run(%{
          suite_id: suite.id,
          prompt_version_id: version.id,
          provider_id: provider.id,
          passed: 0,
          failed: 0
        })

      metrics = Evolution.get_metrics(prompt.id)
      assert [metric] = metrics
      assert metric.avg_pass_rate == nil
    end

    test "provider breakdown includes cost and latency" do
      prompt = prompt_fixture()
      {:ok, version} = Prompts.create_prompt_version(prompt, "Test {{var}}")
      provider1 = provider_fixture(%{name: "OpenAI"})
      provider2 = provider_fixture(%{name: "Anthropic"})
      suite = suite_fixture(%{prompt_id: prompt.id})

      {:ok, _sr1} =
        Evals.create_suite_run(%{
          suite_id: suite.id,
          prompt_version_id: version.id,
          provider_id: provider1.id,
          passed: 5,
          failed: 0,
          avg_cost_usd: Decimal.new("0.004"),
          avg_latency_ms: 350,
          avg_score: Decimal.new("82.5")
        })

      {:ok, _sr2} =
        Evals.create_suite_run(%{
          suite_id: suite.id,
          prompt_version_id: version.id,
          provider_id: provider2.id,
          passed: 5,
          failed: 0,
          avg_cost_usd: Decimal.new("0.006"),
          avg_latency_ms: 420,
          avg_score: Decimal.new("95.0")
        })

      [metrics] = Evolution.get_metrics(prompt.id)

      assert length(metrics.provider_breakdown) == 2

      openai = Enum.find(metrics.provider_breakdown, &(&1.provider_name == "OpenAI"))
      assert Decimal.equal?(openai.avg_cost_usd, Decimal.new("0.004"))
      assert openai.avg_latency_ms == 350
      assert Decimal.equal?(openai.avg_score, Decimal.new("82.5"))

      anthropic = Enum.find(metrics.provider_breakdown, &(&1.provider_name == "Anthropic"))
      assert Decimal.equal?(anthropic.avg_cost_usd, Decimal.new("0.006"))
      assert anthropic.avg_latency_ms == 420
      assert Decimal.equal?(anthropic.avg_score, Decimal.new("95.0"))
    end

    test "computes outcome-weighted efficiency overall and by provider" do
      prompt = prompt_fixture()
      provider = provider_fixture(%{name: "Efficient Provider"})
      {:ok, version} = Prompts.create_prompt_version(prompt, "Test {{var}}")
      suite = suite_fixture(%{prompt_id: prompt.id})

      {:ok, _suite_run} =
        Evals.create_suite_run(%{
          suite_id: suite.id,
          prompt_version_id: version.id,
          provider_id: provider.id,
          passed: 5,
          failed: 5,
          avg_cost_usd: Decimal.new("0.01"),
          avg_latency_ms: 200
        })

      [metric] = Evolution.get_metrics(prompt.id)
      [breakdown] = metric.provider_breakdown

      assert metric.cost_per_passed_test == 0.02
      assert metric.latency_per_passed_test == 400.0
      assert metric.efficiency_status == :available
      assert breakdown.cost_per_passed_test == 0.02
      assert breakdown.latency_per_passed_test == 400.0
    end

    test "marks zero-pass efficiency as unavailable" do
      prompt = prompt_fixture()
      provider = provider_fixture()
      {:ok, version} = Prompts.create_prompt_version(prompt, "Test {{var}}")
      suite = suite_fixture(%{prompt_id: prompt.id})

      {:ok, _suite_run} =
        Evals.create_suite_run(%{
          suite_id: suite.id,
          prompt_version_id: version.id,
          provider_id: provider.id,
          passed: 0,
          failed: 5,
          avg_cost_usd: Decimal.new("0.01"),
          avg_latency_ms: 200
        })

      [metric] = Evolution.get_metrics(prompt.id)

      assert metric.efficiency_status == :no_passes
      assert metric.cost_per_passed_test == nil
      assert metric.latency_per_passed_test == nil
    end

    test "adds stability and adjacent-version regression signals" do
      prompt = prompt_fixture()
      provider = provider_fixture()
      {:ok, v1} = Prompts.create_prompt_version(prompt, "Version 1")
      {:ok, v2} = Prompts.create_prompt_version(prompt, "Version 2")
      suite = suite_fixture(%{prompt_id: prompt.id})

      for {version, passed, failed, cost, latency} <- [
            {v1, 10, 0, "0.01", 100},
            {v1, 10, 0, "0.01", 100},
            {v2, 10, 0, "0.02", 130},
            {v2, 0, 10, "0.02", 130}
          ] do
        {:ok, _suite_run} =
          Evals.create_suite_run(%{
            suite_id: suite.id,
            prompt_version_id: version.id,
            provider_id: provider.id,
            passed: passed,
            failed: failed,
            avg_cost_usd: Decimal.new(cost),
            avg_latency_ms: latency
          })
      end

      [_v1_metric, v2_metric] = Evolution.get_metrics(prompt.id)

      assert v2_metric.pass_rate_stddev == 50.0
      assert v2_metric.signals.stability == :volatile
      assert v2_metric.signals.regressions == [:quality, :cost, :latency]
    end

    test "scopes metrics to one evaluation suite" do
      prompt = prompt_fixture()
      provider = provider_fixture()
      {:ok, version} = Prompts.create_prompt_version(prompt, "Version 1")
      selected_suite = suite_fixture(%{prompt_id: prompt.id})
      other_suite = suite_fixture(%{prompt_id: prompt.id})

      for {suite, passed, failed} <- [
            {selected_suite, 9, 1},
            {other_suite, 0, 10}
          ] do
        {:ok, _suite_run} =
          Evals.create_suite_run(%{
            suite_id: suite.id,
            prompt_version_id: version.id,
            provider_id: provider.id,
            passed: passed,
            failed: failed,
            avg_cost_usd: Decimal.new("0.01"),
            avg_latency_ms: 200
          })
      end

      [metric] = Evolution.get_metrics(prompt.id, suite_id: selected_suite.id)

      assert metric.total_runs == 1
      assert metric.avg_pass_rate == 90.0
    end
  end

  describe "calculate_avg_cost from suite_runs" do
    test "returns nil for empty list" do
      assert Evolution.calculate_avg_cost([]) == nil
    end

    test "returns nil when all costs are nil" do
      suite_runs = [
        %{avg_cost_usd: nil},
        %{avg_cost_usd: nil}
      ]

      assert Evolution.calculate_avg_cost(suite_runs) == nil
    end

    test "averages non-nil costs only" do
      suite_runs = [
        %{avg_cost_usd: Decimal.new("0.004")},
        %{avg_cost_usd: nil},
        %{avg_cost_usd: Decimal.new("0.006")}
      ]

      result = Evolution.calculate_avg_cost(suite_runs)
      assert Decimal.equal?(result, Decimal.new("0.005"))
    end

    test "calculates average correctly" do
      suite_runs = [
        %{avg_cost_usd: Decimal.new("0.004")},
        %{avg_cost_usd: Decimal.new("0.006")},
        %{avg_cost_usd: Decimal.new("0.005")}
      ]

      result = Evolution.calculate_avg_cost(suite_runs)
      assert Decimal.equal?(result, Decimal.new("0.005"))
    end
  end

  describe "calculate_avg_latency from suite_runs" do
    test "returns nil for empty list" do
      assert Evolution.calculate_avg_latency([]) == nil
    end

    test "returns nil when all latencies are nil" do
      suite_runs = [
        %{avg_latency_ms: nil},
        %{avg_latency_ms: nil}
      ]

      assert Evolution.calculate_avg_latency(suite_runs) == nil
    end

    test "averages non-nil latencies only" do
      suite_runs = [
        %{avg_latency_ms: 400},
        %{avg_latency_ms: nil},
        %{avg_latency_ms: 600}
      ]

      assert Evolution.calculate_avg_latency(suite_runs) == 500
    end

    test "rounds to nearest integer" do
      suite_runs = [
        %{avg_latency_ms: 350},
        %{avg_latency_ms: 420},
        %{avg_latency_ms: 390}
      ]

      # (350 + 420 + 390) / 3 = 386.67 -> 387
      assert Evolution.calculate_avg_latency(suite_runs) == 387
    end
  end

  describe "prepare_chart_data/1" do
    test "transforms metrics into chart-ready structure" do
      metrics = [
        %{
          version_number: 1,
          avg_pass_rate: 78.5,
          avg_cost_usd: 0.021,
          avg_latency_ms: 480,
          avg_score: 74.0,
          provider_breakdown: [
            %{
              provider_name: "OpenAI",
              avg_pass_rate: 80.0,
              avg_cost_usd: 0.020,
              avg_latency_ms: 450,
              avg_score: 76.0
            },
            %{
              provider_name: "Anthropic",
              avg_pass_rate: 77.0,
              avg_cost_usd: 0.022,
              avg_latency_ms: 510,
              avg_score: 72.0
            }
          ]
        },
        %{
          version_number: 2,
          avg_pass_rate: 85.2,
          avg_cost_usd: 0.019,
          avg_latency_ms: 420,
          avg_score: 88.5,
          provider_breakdown: [
            %{
              provider_name: "OpenAI",
              avg_pass_rate: 87.0,
              avg_cost_usd: 0.018,
              avg_latency_ms: 400,
              avg_score: 90.0
            },
            %{
              provider_name: "Anthropic",
              avg_pass_rate: 83.5,
              avg_cost_usd: 0.020,
              avg_latency_ms: 440,
              avg_score: 87.0
            }
          ]
        }
      ]

      result = Evolution.prepare_chart_data(metrics)

      assert result.versions == [1, 2]
      assert result.overall.pass_rates == [78.5, 85.2]
      assert result.overall.costs == [0.021, 0.019]
      assert result.overall.latencies == [480, 420]
      assert result.overall.scores == [74.0, 88.5]
      assert result.by_provider["OpenAI"].pass_rates == [80.0, 87.0]
      assert result.by_provider["OpenAI"].costs == [0.020, 0.018]
      assert result.by_provider["OpenAI"].latencies == [450, 400]
      assert result.by_provider["OpenAI"].scores == [76.0, 90.0]
      assert result.by_provider["Anthropic"].pass_rates == [77.0, 83.5]
      assert result.by_provider["Anthropic"].costs == [0.022, 0.020]
      assert result.by_provider["Anthropic"].latencies == [510, 440]
      assert result.by_provider["Anthropic"].scores == [72.0, 87.0]
    end

    test "handles nil values gracefully" do
      metrics = [
        %{
          version_number: 1,
          avg_pass_rate: nil,
          avg_cost_usd: nil,
          avg_latency_ms: nil,
          avg_score: nil,
          provider_breakdown: []
        },
        %{
          version_number: 2,
          avg_pass_rate: 85.2,
          avg_cost_usd: 0.019,
          avg_latency_ms: 420,
          avg_score: 88.5,
          provider_breakdown: []
        }
      ]

      result = Evolution.prepare_chart_data(metrics)

      assert result.versions == [1, 2]
      assert result.overall.pass_rates == [nil, 85.2]
      assert result.overall.costs == [nil, 0.019]
      assert result.overall.latencies == [nil, 420]
      assert result.overall.scores == [nil, 88.5]
      assert result.by_provider == %{}
    end

    test "handles empty metrics list" do
      result = Evolution.prepare_chart_data([])

      assert result.versions == []
      assert result.overall.pass_rates == []
      assert result.overall.costs == []
      assert result.overall.latencies == []
      assert result.overall.scores == []
      assert result.by_provider == %{}
    end
  end
end
