defmodule Aludel.Prompts.Evolution do
  @moduledoc """
  Functions for analyzing prompt version evolution and performance
  metrics.
  """

  import Ecto.Query

  alias Aludel.Evals.SuiteRun
  alias Aludel.Prompts.Evolution.Deltas
  alias Aludel.Prompts.PromptVersion
  alias Aludel.Providers.Provider

  @doc """
  Returns aggregated metrics for all versions of a prompt.

  Returns list of maps with structure:
  - version_id: binary_id
  - version_number: integer
  - created_at: datetime
  - total_runs: integer (suite runs only)
  - avg_pass_rate: float | nil
  - avg_score: Decimal.t() | nil
  - avg_cost_usd: Decimal.t() | nil
  - avg_latency_ms: integer | nil
  - provider_breakdown: list of provider-specific metrics
  """
  @spec get_metrics(binary()) :: [map()]
  def get_metrics(prompt_id) do
    prompt_id
    |> get_versions()
    |> Enum.map(&build_version_metrics/1)
    |> Deltas.annotate()
  end

  @doc false
  def calculate_avg_cost([]), do: nil

  @doc false
  def calculate_avg_cost(suite_runs) do
    costs =
      suite_runs
      |> Enum.map(& &1.avg_cost_usd)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(costs) do
      nil
    else
      avg = Enum.reduce(costs, Decimal.new("0"), &Decimal.add/2)
      avg = Decimal.div(avg, Decimal.new(length(costs)))
      Decimal.round(avg, 4)
    end
  end

  @doc false
  def calculate_avg_latency([]), do: nil

  @doc false
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
  def calculate_avg_score([]), do: nil

  @doc false
  def calculate_avg_score(suite_runs) do
    scores =
      suite_runs
      |> Enum.map(& &1.avg_score)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(scores) do
      nil
    else
      avg = Enum.reduce(scores, Decimal.new("0"), &Decimal.add/2)
      avg = Decimal.div(avg, Decimal.new(length(scores)))
      Decimal.round(avg, 1)
    end
  end

  @doc """
  Prepares metrics data for Chart.js visualization.

  Returns map with structure:
  - versions: list of version numbers
  - overall: aggregated metrics across all providers
  - by_provider: metrics grouped by provider name
  """
  @spec prepare_chart_data([map()]) :: map()
  def prepare_chart_data(metrics) do
    %{
      versions: extract_versions(metrics),
      overall: extract_overall_metrics(metrics),
      by_provider: extract_provider_metrics(metrics)
    }
  end

  # Private functions

  defp get_versions(prompt_id) do
    PromptVersion
    |> where([v], v.prompt_id == ^prompt_id)
    |> order_by([v], asc: v.version)
    |> repo().all()
  end

  defp build_version_metrics(version) do
    suite_runs = get_suite_runs(version.id)

    %{
      version_id: version.id,
      version_number: version.version,
      created_at: version.inserted_at,
      total_runs: length(suite_runs),
      avg_pass_rate: calculate_avg_pass_rate(suite_runs),
      avg_score: calculate_avg_score(suite_runs),
      avg_cost_usd: calculate_avg_cost(suite_runs),
      avg_latency_ms: calculate_avg_latency(suite_runs),
      provider_breakdown: build_provider_breakdown(suite_runs)
    }
  end

  defp get_suite_runs(version_id) do
    SuiteRun
    |> where([sr], sr.prompt_version_id == ^version_id)
    |> repo().all()
  end

  defp calculate_avg_pass_rate([]), do: nil

  defp calculate_avg_pass_rate(suite_runs) do
    total_tests =
      Enum.reduce(suite_runs, 0, fn sr, acc ->
        acc + sr.passed + sr.failed
      end)

    if total_tests == 0 do
      nil
    else
      total_passed = Enum.reduce(suite_runs, 0, fn sr, acc -> acc + sr.passed end)
      Float.round(total_passed / total_tests * 100, 2)
    end
  end

  defp build_provider_breakdown([]), do: []

  defp build_provider_breakdown(suite_runs) do
    provider_ids =
      suite_runs
      |> Enum.map(& &1.provider_id)
      |> Enum.uniq()

    providers =
      Provider
      |> where([p], p.id in ^provider_ids)
      |> repo().all()
      |> Map.new(&{&1.id, &1})

    suite_runs
    |> Enum.group_by(& &1.provider_id)
    |> Enum.map(fn {provider_id, runs} ->
      provider = Map.fetch!(providers, provider_id)

      total_tests = Enum.reduce(runs, 0, fn sr, acc -> acc + sr.passed + sr.failed end)
      total_passed = Enum.reduce(runs, 0, fn sr, acc -> acc + sr.passed end)

      avg_pass_rate =
        if total_tests == 0 do
          nil
        else
          Float.round(total_passed / total_tests * 100, 2)
        end

      %{
        provider_id: provider_id,
        provider_name: provider.name,
        runs: length(runs),
        avg_pass_rate: avg_pass_rate,
        avg_score: calculate_avg_score(runs),
        avg_cost_usd: calculate_avg_cost(runs),
        avg_latency_ms: calculate_avg_latency(runs)
      }
    end)
    |> Enum.sort_by(& &1.provider_name)
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
    |> Enum.group_by(fn {provider_name, _version, _breakdown} ->
      provider_name
    end)
    |> Enum.map(fn {provider_name, entries} ->
      # Sort by version to maintain order
      sorted_entries =
        entries
        |> Enum.sort_by(fn {_name, version, _breakdown} -> version end)

      pass_rates =
        Enum.map(sorted_entries, fn {_name, _version, breakdown} ->
          breakdown.avg_pass_rate
        end)

      scores =
        Enum.map(sorted_entries, fn {_name, _version, breakdown} ->
          decimal_to_float(breakdown.avg_score)
        end)

      costs =
        Enum.map(sorted_entries, fn {_name, _version, breakdown} ->
          decimal_to_float(breakdown.avg_cost_usd)
        end)

      latencies =
        Enum.map(sorted_entries, fn {_name, _version, breakdown} ->
          breakdown.avg_latency_ms
        end)

      {provider_name,
       %{
         pass_rates: pass_rates,
         scores: scores,
         costs: costs,
         latencies: latencies
       }}
    end)
    |> Map.new()
  end

  defp decimal_to_float(nil), do: nil
  defp decimal_to_float(%Decimal{} = value), do: Decimal.to_float(value)
  defp decimal_to_float(value), do: value

  defp repo, do: Aludel.Repo.get()
end
