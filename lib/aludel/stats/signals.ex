defmodule Aludel.Stats.Signals do
  @moduledoc false

  @quality_regression_threshold -5.0
  @efficiency_regression_threshold 20.0

  @spec compare(map(), map()) :: map()
  def compare(current, previous) do
    deltas = %{
      pass_rate: absolute_delta(current[:pass_rate], previous[:pass_rate]),
      cost_per_passed_test:
        relative_delta(current[:cost_per_passed_test], previous[:cost_per_passed_test]),
      avg_latency_ms: relative_delta(current[:avg_latency_ms], previous[:avg_latency_ms])
    }

    %{
      deltas: deltas,
      regressions: regressions(deltas),
      stability: stability(current)
    }
  end

  defp regressions(deltas) do
    []
    |> maybe_add(:quality, regression?(deltas.pass_rate, :quality))
    |> maybe_add(:cost, regression?(deltas.cost_per_passed_test, :efficiency))
    |> maybe_add(:latency, regression?(deltas.avg_latency_ms, :efficiency))
  end

  defp regression?(value, :quality) when is_number(value) do
    value <= @quality_regression_threshold
  end

  defp regression?(value, :efficiency) when is_number(value) do
    value >= @efficiency_regression_threshold
  end

  defp regression?(_value, _kind) do
    false
  end

  defp maybe_add(items, item, true) do
    items ++ [item]
  end

  defp maybe_add(items, _item, false) do
    items
  end

  defp stability(%{stability_sample_size: sample_size}) when sample_size < 2 do
    :insufficient_data
  end

  defp stability(%{pass_rate_stddev: stddev}) when is_number(stddev) and stddev < 5 do
    :stable
  end

  defp stability(%{pass_rate_stddev: stddev}) when is_number(stddev) and stddev < 15 do
    :variable
  end

  defp stability(%{pass_rate_stddev: stddev}) when is_number(stddev) do
    :volatile
  end

  defp stability(_current) do
    :insufficient_data
  end

  defp absolute_delta(current, previous)
       when is_number(current) and is_number(previous) do
    current
    |> Kernel.-(previous)
    |> Float.round(2)
  end

  defp absolute_delta(_current, _previous) do
    nil
  end

  defp relative_delta(current, previous)
       when is_number(current) and is_number(previous) and previous > 0 do
    current
    |> Kernel.-(previous)
    |> Kernel./(previous)
    |> Kernel.*(100)
    |> Float.round(2)
  end

  defp relative_delta(_current, _previous) do
    nil
  end
end
