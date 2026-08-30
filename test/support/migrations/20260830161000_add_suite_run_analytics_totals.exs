defmodule Aludel.TestRepo.Migrations.AddSuiteRunAnalyticsTotals do
  use Ecto.Migration

  def up do
    alter table(:suite_runs) do
      add :total_cost_usd, :decimal, precision: 18, scale: 8
      add :cost_sample_count, :integer, null: false, default: 0
      add :total_latency_ms, :bigint
      add :latency_sample_count, :integer, null: false, default: 0
    end

    execute("""
    UPDATE suite_runs AS suite_run
    SET total_cost_usd = summary.total_cost_usd,
        cost_sample_count = summary.cost_sample_count,
        total_latency_ms = summary.total_latency_ms,
        latency_sample_count = summary.latency_sample_count
    FROM (
      SELECT suite_runs.id,
             SUM((result.value->>'cost_usd')::numeric)
               FILTER (WHERE jsonb_typeof(result.value->'cost_usd') = 'number') AS total_cost_usd,
             COUNT(*)
               FILTER (WHERE jsonb_typeof(result.value->'cost_usd') = 'number')::integer AS cost_sample_count,
             ROUND(SUM((result.value->>'latency_ms')::numeric)
               FILTER (WHERE jsonb_typeof(result.value->'latency_ms') = 'number'))::bigint AS total_latency_ms,
             COUNT(*)
               FILTER (WHERE jsonb_typeof(result.value->'latency_ms') = 'number')::integer AS latency_sample_count
      FROM suite_runs
      LEFT JOIN LATERAL jsonb_array_elements(suite_runs.results) AS result(value) ON TRUE
      GROUP BY suite_runs.id
    ) AS summary
    WHERE suite_run.id = summary.id
    """)
  end

  def down do
    alter table(:suite_runs) do
      remove :latency_sample_count
      remove :total_latency_ms
      remove :cost_sample_count
      remove :total_cost_usd
    end
  end
end
