defmodule Aludel.Prompts.OptimizationTest do
  use ExUnit.Case, async: true

  alias Aludel.Prompts.Optimization

  test "keeps non-dominated trade-offs on the Pareto frontier" do
    metrics = [
      metric(1, 90.0, 0.02, 300.0),
      metric(2, 90.0, 0.01, 250.0),
      metric(3, 95.0, 0.03, 400.0),
      metric(4, 80.0, nil, 200.0)
    ]

    analysis = Optimization.analyze(metrics)

    assert Enum.map(analysis.frontier, & &1.version_number) == [2, 3]
    assert Enum.find(analysis.candidates, &(&1.version_number == 1)).pareto_status == :dominated

    assert Enum.find(analysis.candidates, &(&1.version_number == 4)).pareto_status ==
             :insufficient
  end

  test "requires at least one strict improvement to dominate a candidate" do
    metrics = [
      metric(1, 90.0, 0.01, 250.0),
      metric(2, 90.0, 0.01, 250.0)
    ]

    assert Optimization.analyze(metrics).frontier |> Enum.map(& &1.version_number) == [1, 2]
  end

  defp metric(version, pass_rate, cost_per_pass, latency_per_pass) do
    %{
      version_number: version,
      avg_pass_rate: pass_rate,
      cost_per_passed_test: cost_per_pass,
      latency_per_passed_test: latency_per_pass
    }
  end
end
