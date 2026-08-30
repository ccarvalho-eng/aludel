defmodule Aludel.Prompts.Evolution do
  @moduledoc """
  Functions for analyzing prompt version evolution and performance metrics.
  """

  import Ecto.Query

  alias Aludel.Evals.SuiteRun
  alias Aludel.Prompts.Evolution.Deltas
  alias Aludel.Prompts.PromptVersion
  alias Aludel.Providers.Provider

  @doc """
  Returns aggregated metrics for all versions of a prompt.

  The optional `:days` and `:as_of` values bound suite-run analysis while
  retaining every prompt version in the result.
  """
  @spec get_metrics(binary(), keyword()) :: [map()]
  def get_metrics(prompt_id, opts \\ []) do
    versions = get_versions(prompt_id)
    runs_by_version = get_suite_runs(versions, opts)

    versions
    |> Enum.map(fn version ->
      build_version_metrics(version, Map.get(runs_by_version, version.id, []))
    end)
    |> Deltas.annotate()
  end

  @doc false
  def calculate_avg_cost([]) do
    nil
  end

  def calculate_avg_cost(suite_runs) do
    costs =
      suite_runs
      |> Enum.map(& &1.avg_cost_usd)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(costs) do
      nil
    else
      costs
      |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)
      |> Decimal.div(Decimal.new(length(costs)))
      |> Decimal.round(4)
    end
  end

  @doc false
  def calculate_avg_latency([]) do
    nil
  end

  def calculate_avg_latency(suite_runs) do
    latencies =
      suite_runs
      |> Enum.map(& &1.avg_latency_ms)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(latencies) do
      nil
    else
      round(Enum.sum(latencies) / length(latencies))
    end
  end

  @doc false
  def calculate_avg_score([]) do
    nil
  end

  def calculate_avg_score(suite_runs) do
    scores =
      suite_runs
      |> Enum.map(& &1.avg_score)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(scores) do
      nil
    else
      scores
      |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)
      |> Decimal.div(Decimal.new(length(scores)))
      |> Decimal.round(1)
    end
  end

  @doc """
  Prepares metrics data for Chart.js visualization.
  """
  @spec prepare_chart_data([map()]) :: map()
  def prepare_chart_data(metrics) do
    %{
      versions: extract_versions(metrics),
      overall: extract_overall_metrics(metrics),
      by_provider: extract_provider_metrics(metrics)
    }
  end

  defp get_versions(prompt_id) do
    PromptVersion
    |> where([version], version.prompt_id == ^prompt_id)
    |> order_by([version], asc: version.version)
    |> repo().all()
  end

  defp get_suite_runs([], _opts) do
    %{}
  end

  defp get_suite_runs(versions, opts) do
    version_ids = Enum.map(versions, & &1.id)

    SuiteRun
    |> join(:inner, [suite_run], provider in Provider, on: provider.id == suite_run.provider_id)
    |> where([suite_run], suite_run.prompt_version_id in ^version_ids)
    |> maybe_bound_runs(opts)
    |> select([suite_run, provider], %{
      prompt_version_id: suite_run.prompt_version_id,
      provider_id: suite_run.provider_id,
      provider_name: provider.name,
      passed: suite_run.passed,
      failed: suite_run.failed,
      avg_cost_usd: suite_run.avg_cost_usd,
      avg_latency_ms: suite_run.avg_latency_ms,
      avg_score: suite_run.avg_score,
      total_cost_usd: suite_run.total_cost_usd,
      cost_sample_count: suite_run.cost_sample_count,
      total_latency_ms: suite_run.total_latency_ms,
      latency_sample_count: suite_run.latency_sample_count
    })
    |> repo().all()
    |> Enum.group_by(& &1.prompt_version_id)
  end

  defp maybe_bound_runs(query, opts) do
    case Keyword.get(opts, :days) do
      days when is_integer(days) and days > 0 ->
        as_of = opts |> Keyword.get(:as_of, current_as_of()) |> DateTime.truncate(:second)
        starts_at = DateTime.add(as_of, -days, :day)

        where(
          query,
          [suite_run],
          suite_run.inserted_at >= ^starts_at and suite_run.inserted_at < ^as_of
        )

      nil ->
        query

      _invalid ->
        raise ArgumentError, ":days must be a positive integer"
    end
  end

  defp build_version_metrics(version, suite_runs) do
    suite_runs
    |> aggregate_metrics()
    |> Map.merge(%{
      version_id: version.id,
      version_number: version.version,
      created_at: version.inserted_at,
      provider_breakdown: build_provider_breakdown(suite_runs)
    })
  end

  defp aggregate_metrics(suite_runs) do
    passed = Enum.sum(Enum.map(suite_runs, & &1.passed))
    failed = Enum.sum(Enum.map(suite_runs, & &1.failed))
    total_tests = passed + failed
    total_cost = Enum.reduce(suite_runs, nil, &sum_optional(exact_cost(&1), &2))
    total_latency = Enum.reduce(suite_runs, nil, &sum_optional(exact_latency(&1), &2))

    %{
      total_runs: length(suite_runs),
      avg_pass_rate: percentage(passed, total_tests),
      avg_score: calculate_avg_score(suite_runs),
      avg_cost_usd: calculate_avg_cost(suite_runs),
      avg_latency_ms: calculate_avg_latency(suite_runs),
      cost_per_passed_test: ratio(total_cost, passed),
      latency_per_passed_test: ratio(total_latency, passed),
      efficiency_status: efficiency_status(total_tests, passed),
      pass_rate_stddev: pass_rate_stddev(suite_runs),
      stability_sample_size: Enum.count(suite_runs, &(test_count(&1) > 0))
    }
  end

  defp build_provider_breakdown([]) do
    []
  end

  defp build_provider_breakdown(suite_runs) do
    suite_runs
    |> Enum.group_by(& &1.provider_id)
    |> Enum.map(fn {provider_id, runs} ->
      runs
      |> aggregate_metrics()
      |> Map.merge(%{
        provider_id: provider_id,
        provider_name: List.first(runs).provider_name,
        runs: length(runs)
      })
    end)
    |> Enum.sort_by(& &1.provider_name)
  end

  defp exact_cost(%{total_cost_usd: %Decimal{}, cost_sample_count: samples} = run)
       when samples > 0 do
    Decimal.to_float(run.total_cost_usd)
  end

  defp exact_cost(%{avg_cost_usd: %Decimal{} = average} = run) do
    Decimal.to_float(average) * test_count(run)
  end

  defp exact_cost(_run) do
    nil
  end

  defp exact_latency(%{total_latency_ms: total, latency_sample_count: samples})
       when is_integer(total) and samples > 0 do
    total * 1.0
  end

  defp exact_latency(%{avg_latency_ms: average} = run) when is_integer(average) do
    average * test_count(run) * 1.0
  end

  defp exact_latency(_run) do
    nil
  end

  defp test_count(run) do
    run.passed + run.failed
  end

  defp percentage(_numerator, 0) do
    nil
  end

  defp percentage(numerator, denominator) do
    Float.round(numerator / denominator * 100, 2)
  end

  defp ratio(nil, _denominator) do
    nil
  end

  defp ratio(_numerator, 0) do
    nil
  end

  defp ratio(numerator, denominator) do
    Float.round(numerator / denominator, 4)
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

  defp pass_rate_stddev(suite_runs) do
    rates =
      suite_runs
      |> Enum.filter(&(test_count(&1) > 0))
      |> Enum.map(&percentage(&1.passed, test_count(&1)))

    case rates do
      [] ->
        nil

      _rates ->
        mean = Enum.sum(rates) / length(rates)
        variance = Enum.sum(Enum.map(rates, &:math.pow(&1 - mean, 2))) / length(rates)
        Float.round(:math.sqrt(variance), 2)
    end
  end

  defp sum_optional(nil, nil) do
    nil
  end

  defp sum_optional(nil, total) do
    total
  end

  defp sum_optional(value, nil) do
    value
  end

  defp sum_optional(value, total) do
    value + total
  end

  defp extract_versions(metrics) do
    Enum.map(metrics, & &1.version_number)
  end

  defp extract_overall_metrics(metrics) do
    %{
      pass_rates: Enum.map(metrics, & &1.avg_pass_rate),
      scores: Enum.map(metrics, &decimal_to_float(&1.avg_score)),
      costs: Enum.map(metrics, &decimal_to_float(&1.avg_cost_usd)),
      latencies: Enum.map(metrics, & &1.avg_latency_ms)
    }
  end

  defp extract_provider_metrics(metrics) do
    metrics
    |> Enum.flat_map(fn metric ->
      Enum.map(metric.provider_breakdown, fn breakdown ->
        {breakdown.provider_name, metric.version_number, breakdown}
      end)
    end)
    |> Enum.group_by(fn {provider_name, _version, _breakdown} -> provider_name end)
    |> Map.new(fn {provider_name, entries} ->
      sorted_entries = Enum.sort_by(entries, fn {_name, version, _breakdown} -> version end)

      {provider_name,
       %{
         pass_rates: extract_provider_values(sorted_entries, :avg_pass_rate),
         scores: extract_provider_values(sorted_entries, :avg_score, &decimal_to_float/1),
         costs: extract_provider_values(sorted_entries, :avg_cost_usd, &decimal_to_float/1),
         latencies: extract_provider_values(sorted_entries, :avg_latency_ms)
       }}
    end)
  end

  defp extract_provider_values(entries, key, transform \\ &Function.identity/1) do
    Enum.map(entries, fn {_name, _version, breakdown} ->
      breakdown |> Map.fetch!(key) |> transform.()
    end)
  end

  defp decimal_to_float(nil) do
    nil
  end

  defp decimal_to_float(%Decimal{} = value) do
    Decimal.to_float(value)
  end

  defp decimal_to_float(value) do
    value
  end

  defp repo do
    Aludel.Repo.get()
  end

  defp current_as_of do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.add(1, :second)
  end
end
