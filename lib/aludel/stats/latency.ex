defmodule Aludel.Stats.Latency do
  @moduledoc """
  Latency reporting and provider breakdowns.
  """

  import Ecto.Query

  alias Aludel.Runs.RunResult
  alias Aludel.Stats.Shared

  @doc """
  Returns the median and 95th-percentile latency for recorded prompt results.

  Both values are zero when no latency samples are available.
  """
  @spec latency_percentiles() :: %{p50: number(), p95: number()}
  def latency_percentiles do
    result =
      from(rr in RunResult,
        where: not is_nil(rr.latency_ms),
        select: %{
          p50:
            fragment(
              "percentile_disc(0.5) WITHIN GROUP (ORDER BY ?)",
              rr.latency_ms
            ),
          p95:
            fragment(
              "percentile_disc(0.95) WITHIN GROUP (ORDER BY ?)",
              rr.latency_ms
            )
        }
      )
      |> Shared.repo().one()

    case result do
      nil ->
        %{p50: 0, p95: 0}

      %{p50: p50, p95: p95} ->
        %{
          p50: Shared.to_float(p50) |> Float.round(0),
          p95: Shared.to_float(p95) |> Float.round(0)
        }
    end
  end

  @doc """
  Aggregates prompt-result latency statistics by provider.

  Results are ordered from lowest to highest average latency.
  """
  @spec latency_by_provider() :: [map()]
  def latency_by_provider do
    from(rr in RunResult,
      join: p in assoc(rr, :provider),
      where: not is_nil(rr.latency_ms),
      group_by: [p.id, p.name, p.provider],
      select: %{
        provider_name: p.name,
        provider: p.provider,
        avg_latency: avg(rr.latency_ms),
        min_latency: min(rr.latency_ms),
        max_latency: max(rr.latency_ms),
        run_count: count(rr.id)
      }
    )
    |> Shared.repo().all()
    |> Enum.map(fn row ->
      %{
        provider_name: row.provider_name,
        provider: row.provider,
        avg_latency: Shared.to_float(row.avg_latency),
        min_latency: Shared.to_float(row.min_latency),
        max_latency: Shared.to_float(row.max_latency),
        run_count: row.run_count
      }
    end)
    |> Enum.sort_by(& &1.avg_latency)
  end
end
