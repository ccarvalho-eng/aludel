defmodule Aludel.Prompts.Evolution.Deltas do
  @moduledoc false

  @delta_keys [:pass_rate, :cost_usd, :latency_ms]

  @spec annotate([map()]) :: [map()]
  def annotate(metrics) do
    {annotated_metrics, _previous_metric} =
      Enum.map_reduce(metrics, nil, fn metric, previous_metric ->
        {annotate_metric(metric, previous_metric), metric}
      end)

    annotated_metrics
  end

  defp annotate_metric(metric, previous_metric) do
    previous_providers =
      previous_metric
      |> provider_breakdown()
      |> Map.new(&{&1.provider_id, &1})

    provider_breakdown =
      metric
      |> provider_breakdown()
      |> Enum.map(fn provider_metrics ->
        previous_provider = Map.get(previous_providers, provider_metrics.provider_id)
        Map.put(provider_metrics, :deltas, build_deltas(provider_metrics, previous_provider))
      end)

    metric
    |> Map.put(:deltas, build_deltas(metric, previous_metric))
    |> Map.put(:provider_breakdown, provider_breakdown)
  end

  defp build_deltas(_current, nil) do
    Map.new(@delta_keys, &{&1, nil})
  end

  defp build_deltas(current, previous) do
    %{
      pass_rate: pass_rate_delta(current.avg_pass_rate, previous.avg_pass_rate),
      cost_usd: decimal_delta(current.avg_cost_usd, previous.avg_cost_usd),
      latency_ms: number_delta(current.avg_latency_ms, previous.avg_latency_ms)
    }
  end

  defp provider_breakdown(nil) do
    []
  end

  defp provider_breakdown(metric) do
    Map.get(metric, :provider_breakdown, [])
  end

  defp pass_rate_delta(current, previous)
       when is_number(current) and is_number(previous) do
    current
    |> Kernel.-(previous)
    |> Float.round(2)
  end

  defp pass_rate_delta(_current, _previous) do
    nil
  end

  defp decimal_delta(%Decimal{} = current, %Decimal{} = previous) do
    Decimal.sub(current, previous)
  end

  defp decimal_delta(_current, _previous) do
    nil
  end

  defp number_delta(current, previous)
       when is_number(current) and is_number(previous) do
    current - previous
  end

  defp number_delta(_current, _previous) do
    nil
  end
end
