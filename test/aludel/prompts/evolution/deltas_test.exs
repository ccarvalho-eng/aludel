defmodule Aludel.Prompts.Evolution.DeltasTest do
  use ExUnit.Case, async: true

  alias Aludel.Prompts.Evolution.Deltas

  test "annotates versions and matching providers against their predecessor" do
    metrics = [
      metric(1, 60.0, "0.0100", 500),
      metric(2, 90.0, "0.0080", 420)
    ]

    [first, second] = Deltas.annotate(metrics)

    assert first.deltas == %{pass_rate: nil, cost_usd: nil, latency_ms: nil}
    assert second.deltas.pass_rate == 30.0
    assert Decimal.equal?(second.deltas.cost_usd, Decimal.new("-0.0020"))
    assert second.deltas.latency_ms == -80

    [first_provider] = first.provider_breakdown
    [second_provider] = second.provider_breakdown

    assert first_provider.deltas == %{pass_rate: nil, cost_usd: nil, latency_ms: nil}
    assert second_provider.deltas.pass_rate == 30.0
    assert Decimal.equal?(second_provider.deltas.cost_usd, Decimal.new("-0.0020"))
    assert second_provider.deltas.latency_ms == -80
  end

  test "leaves deltas empty when there is no comparable value or provider" do
    first =
      metric(1, nil, nil, nil)
      |> Map.put(:provider_breakdown, [])

    second = metric(2, 90.0, "0.0080", 420)

    [_first, annotated_second] = Deltas.annotate([first, second])

    assert annotated_second.deltas == %{pass_rate: nil, cost_usd: nil, latency_ms: nil}

    [provider] = annotated_second.provider_breakdown
    assert provider.deltas == %{pass_rate: nil, cost_usd: nil, latency_ms: nil}
  end

  defp metric(version_number, pass_rate, cost, latency) do
    %{
      version_number: version_number,
      avg_pass_rate: pass_rate,
      avg_cost_usd: decimal(cost),
      avg_latency_ms: latency,
      provider_breakdown: [
        %{
          provider_id: "provider-1",
          avg_pass_rate: pass_rate,
          avg_cost_usd: decimal(cost),
          avg_latency_ms: latency
        }
      ]
    }
  end

  defp decimal(nil) do
    nil
  end

  defp decimal(value) do
    Decimal.new(value)
  end
end
