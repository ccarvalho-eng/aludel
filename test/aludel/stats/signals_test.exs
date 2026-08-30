defmodule Aludel.Stats.SignalsTest do
  use ExUnit.Case, async: true

  alias Aludel.Stats.Signals

  test "flags bounded quality, cost, and latency regressions" do
    previous = %{
      pass_rate: 100.0,
      cost_per_passed_test: 0.01,
      avg_latency_ms: 100.0
    }

    current = %{
      pass_rate: 50.0,
      cost_per_passed_test: 0.02,
      avg_latency_ms: 130.0,
      pass_rate_stddev: 50.0,
      stability_sample_size: 2
    }

    comparison = Signals.compare(current, previous)

    assert comparison.deltas.pass_rate == -50.0
    assert comparison.deltas.cost_per_passed_test == 100.0
    assert comparison.deltas.avg_latency_ms == 30.0
    assert comparison.regressions == [:quality, :cost, :latency]
    assert comparison.stability == :volatile
  end

  test "requires enough samples for a stability classification" do
    comparison =
      Signals.compare(
        %{pass_rate_stddev: 0.0, stability_sample_size: 1},
        %{}
      )

    assert comparison.stability == :insufficient_data
    assert comparison.regressions == []
  end

  test "does not manufacture ratios when a previous metric is zero or missing" do
    comparison =
      Signals.compare(
        %{cost_per_passed_test: 0.02, avg_latency_ms: nil},
        %{cost_per_passed_test: 0.0, avg_latency_ms: 100.0}
      )

    assert comparison.deltas.cost_per_passed_test == nil
    assert comparison.deltas.avg_latency_ms == nil
    assert comparison.regressions == []
  end
end
