defmodule Aludel.Stats.Overview do
  @moduledoc """
  Top-line dashboard metrics and bounded period comparisons.
  """

  import Ecto.Query

  alias Aludel.Evals.SuiteRun
  alias Aludel.Runs.{Run, RunResult}
  alias Aludel.Stats.{Shared, Signals}
  alias Ecto.Adapters.SQL

  @suite_period_sql """
  WITH windows AS (
    SELECT days,
           $2::timestamptz - make_interval(days => days) AS current_start,
           $2::timestamptz - make_interval(days => days * 2) AS previous_start
    FROM unnest($1::integer[]) AS days
  ), periods AS (
    SELECT days, 'current' AS period, current_start AS starts_at, $2::timestamptz AS ends_at
    FROM windows
    UNION ALL
    SELECT days, 'previous' AS period, previous_start AS starts_at, current_start AS ends_at
    FROM windows
  )
  SELECT periods.days,
         periods.period,
         COUNT(suite_runs.id)::bigint AS suite_runs,
         COALESCE(SUM(suite_runs.passed), 0)::bigint AS passed,
         COALESCE(SUM(suite_runs.failed), 0)::bigint AS failed,
         SUM(
           COALESCE(
             suite_runs.total_cost_usd,
             suite_runs.avg_cost_usd * (suite_runs.passed + suite_runs.failed)
           )
         ) AS total_cost_usd,
         SUM(
           COALESCE(
             suite_runs.total_latency_ms,
             suite_runs.avg_latency_ms::bigint * (suite_runs.passed + suite_runs.failed)
           )
         ) AS total_latency_ms,
         SUM(
           CASE
             WHEN suite_runs.latency_sample_count > 0 THEN suite_runs.latency_sample_count
             WHEN suite_runs.avg_latency_ms IS NOT NULL THEN suite_runs.passed + suite_runs.failed
             ELSE 0
           END
         )::bigint AS latency_sample_count,
         STDDEV_POP(
           100.0 * suite_runs.passed / NULLIF(suite_runs.passed + suite_runs.failed, 0)
         ) AS pass_rate_stddev,
         COUNT(suite_runs.id)
           FILTER (WHERE suite_runs.passed + suite_runs.failed > 0)::bigint AS stability_sample_size
  FROM periods
  LEFT JOIN suite_runs
    ON suite_runs.inserted_at >= periods.starts_at
   AND suite_runs.inserted_at < periods.ends_at
  GROUP BY periods.days, periods.period
  ORDER BY periods.days, periods.period
  """

  @run_period_sql """
  WITH windows AS (
    SELECT days,
           $2::timestamptz - make_interval(days => days) AS current_start,
           $2::timestamptz - make_interval(days => days * 2) AS previous_start
    FROM unnest($1::integer[]) AS days
  ), periods AS (
    SELECT days, 'current' AS period, current_start AS starts_at, $2::timestamptz AS ends_at
    FROM windows
    UNION ALL
    SELECT days, 'previous' AS period, previous_start AS starts_at, current_start AS ends_at
    FROM windows
  )
  SELECT periods.days,
         periods.period,
         COUNT(runs.id)::bigint AS prompt_runs
  FROM periods
  LEFT JOIN runs
    ON runs.inserted_at >= periods.starts_at
   AND runs.inserted_at < periods.ends_at
  GROUP BY periods.days, periods.period
  ORDER BY periods.days, periods.period
  """

  @doc """
  Counts all recorded prompt runs and suite runs.
  """
  @spec total_runs() :: integer()
  def total_runs do
    suite_runs = from(sr in SuiteRun, select: count(sr.id)) |> Shared.repo().one()
    prompt_runs = from(r in Run, select: count(r.id)) |> Shared.repo().one()

    suite_runs + prompt_runs
  end

  @doc """
  Returns total passed and failed tests across suite runs.
  """
  @spec test_totals() :: {integer(), integer()}
  def test_totals do
    query =
      from sr in SuiteRun,
        select: %{
          total_passed: sum(sr.passed),
          total_failed: sum(sr.failed)
        }

    result = Shared.repo().one(query)

    passed = Shared.to_integer(result.total_passed)
    failed = Shared.to_integer(result.total_failed)

    {passed, failed}
  end

  @doc """
  Calculates a percentage success rate, returning `0.0` when no tests exist.
  """
  @spec success_rate(integer(), integer()) :: float()
  def success_rate(passed, failed) do
    total = passed + failed
    if total > 0, do: Float.round(passed / total * 100, 1), else: 0.0
  end

  @doc """
  Compares the current period with the immediately preceding period.

  The period defaults to seven days. Counts, quality, cost, latency, stability,
  regression signals, and total-run trend are calculated with bounded period
  queries.
  """
  @spec comparison_stats(pos_integer()) :: map()
  def comparison_stats(days \\ 7) do
    comparison_stats(days, current_as_of())
  end

  @doc """
  Compares adjacent periods ending at the supplied UTC timestamp.
  """
  @spec comparison_stats(pos_integer(), DateTime.t()) :: map()
  def comparison_stats(days, %DateTime{} = as_of) when is_integer(days) and days > 0 do
    [days]
    |> comparisons(as_of)
    |> Map.fetch!(days)
  end

  @doc """
  Returns seven-day and thirty-day period comparisons keyed by window length.
  """
  @spec rolling_comparisons(DateTime.t()) :: %{pos_integer() => map()}
  def rolling_comparisons(as_of \\ current_as_of()) do
    comparisons([7, 30], as_of)
  end

  @doc """
  Returns average latency across prompt-run results, or zero when unavailable.
  """
  @spec avg_latency() :: number()
  def avg_latency do
    query =
      from rr in RunResult,
        where: not is_nil(rr.latency_ms),
        select: avg(rr.latency_ms)

    case Shared.repo().one(query) do
      nil ->
        0

      %Decimal{} = latency ->
        latency |> Decimal.to_float() |> Float.round(0)

      latency when is_float(latency) ->
        Float.round(latency, 0)

      latency ->
        latency
    end
  end

  defp comparisons(days, as_of) do
    normalized_as_of = DateTime.truncate(as_of, :second)
    suite_rows = query_suite_rows([days, normalized_as_of])
    run_rows = query_run_rows([days, normalized_as_of])
    run_counts = index_run_counts(run_rows)

    suite_rows
    |> Enum.map(&build_period(&1, run_counts))
    |> Enum.group_by(& &1.days)
    |> Map.new(fn {period_days, periods} ->
      current = Enum.find(periods, &(&1.period == "current")).stats
      previous = Enum.find(periods, &(&1.period == "previous")).stats

      {period_days,
       %{
         current: current,
         previous: previous,
         comparison: Signals.compare(current, previous),
         trends: %{total_runs: trend_direction(current.total_runs, previous.total_runs)}
       }}
    end)
  end

  defp query_suite_rows(params) do
    Shared.repo()
    |> SQL.query!(@suite_period_sql, params)
    |> rows_to_maps()
  end

  defp query_run_rows(params) do
    Shared.repo()
    |> SQL.query!(@run_period_sql, params)
    |> rows_to_maps()
  end

  defp rows_to_maps(%{columns: columns, rows: rows}) do
    Enum.map(rows, fn row ->
      columns
      |> Enum.zip(row)
      |> Map.new()
    end)
  end

  defp index_run_counts(rows) do
    Map.new(rows, fn row ->
      {{row["days"], row["period"]}, row["prompt_runs"]}
    end)
  end

  defp build_period(row, run_counts) do
    passed = row["passed"]
    failed = row["failed"]
    total_tests = passed + failed
    total_cost = decimal_to_float(row["total_cost_usd"])
    total_latency = decimal_to_float(row["total_latency_ms"])
    latency_samples = row["latency_sample_count"]
    prompt_runs = Map.fetch!(run_counts, {row["days"], row["period"]})

    stats = %{
      suite_runs: row["suite_runs"],
      prompt_runs: prompt_runs,
      total_runs: row["suite_runs"] + prompt_runs,
      passed: passed,
      failed: failed,
      pass_rate: ratio(passed * 100.0, total_tests),
      total_cost_usd: rounded(total_cost, 8),
      avg_latency_ms: ratio(total_latency, latency_samples),
      cost_per_passed_test: ratio(total_cost, passed),
      latency_per_passed_test: ratio(total_latency, passed),
      pass_rate_stddev: rounded(decimal_to_float(row["pass_rate_stddev"]), 2),
      stability_sample_size: row["stability_sample_size"],
      efficiency_status: efficiency_status(total_tests, passed)
    }

    %{days: row["days"], period: row["period"], stats: stats}
  end

  defp efficiency_status(0, _passed) do
    :no_tests
  end

  defp efficiency_status(_total_tests, 0) do
    :no_passes
  end

  defp efficiency_status(_total_tests, _passed) do
    :available
  end

  defp ratio(nil, _denominator) do
    nil
  end

  defp ratio(_numerator, denominator) when denominator in [nil, 0] do
    nil
  end

  defp ratio(numerator, denominator) do
    numerator
    |> Kernel./(denominator)
    |> Float.round(4)
  end

  defp rounded(nil, _places) do
    nil
  end

  defp rounded(value, places) do
    Float.round(value, places)
  end

  defp decimal_to_float(nil) do
    nil
  end

  defp decimal_to_float(%Decimal{} = value) do
    Decimal.to_float(value)
  end

  defp decimal_to_float(value) when is_integer(value) do
    value * 1.0
  end

  defp decimal_to_float(value) do
    value
  end

  defp trend_direction(current, previous) when previous == 0 and current > 0 do
    :up
  end

  defp trend_direction(current, previous) when current > previous do
    :up
  end

  defp trend_direction(current, previous) when current < previous do
    :down
  end

  defp trend_direction(_current, _previous) do
    :stable
  end

  defp current_as_of do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.add(1, :second)
  end
end
