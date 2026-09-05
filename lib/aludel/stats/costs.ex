defmodule Aludel.Stats.Costs do
  @moduledoc """
  Cost reporting and breakdowns for the dashboard.
  """

  import Ecto.Query

  alias Aludel.Evals.SuiteRun
  alias Aludel.Runs
  alias Aludel.Runs.RunResult
  alias Aludel.Stats.Overview
  alias Aludel.Stats.Shared

  @doc """
  Returns the average recorded cost across prompt runs and suite runs.
  """
  @spec cost_per_run() :: float()
  def cost_per_run do
    total = Overview.total_runs()
    if total > 0, do: Runs.total_cost() / total, else: 0.0
  end

  @doc """
  Aggregates recorded prompt-run and suite-run costs by provider.

  Results are ordered from highest to lowest total cost.
  """
  @spec cost_by_provider() :: [map()]
  def cost_by_provider do
    run_costs =
      from(rr in RunResult,
        join: p in assoc(rr, :provider),
        where: not is_nil(rr.cost_usd),
        group_by: [p.id, p.name, p.provider],
        select: %{
          provider_id: p.id,
          provider_name: p.name,
          provider: p.provider,
          total_cost: sum(rr.cost_usd),
          run_count: count(rr.id)
        }
      )
      |> Shared.repo().all()

    suite_costs =
      from(sr in SuiteRun,
        join: p in assoc(sr, :provider),
        preload: [provider: p]
      )
      |> Shared.repo().all()
      |> Enum.filter(&(Shared.suite_run_cost_entries(&1) > 0))
      |> Enum.map(fn suite_run ->
        %{
          provider_id: suite_run.provider.id,
          provider_name: suite_run.provider.name,
          provider: suite_run.provider.provider,
          total_cost: Shared.suite_run_total_cost(suite_run),
          run_count: 1
        }
      end)

    (run_costs ++ suite_costs)
    |> Enum.group_by(& &1.provider_id)
    |> Enum.map(fn {_provider_id, entries} ->
      total_cost = merge_total_cost(entries)
      run_count = Enum.sum(Enum.map(entries, & &1.run_count))
      first_entry = List.first(entries)

      %{
        provider_name: first_entry.provider_name,
        provider: first_entry.provider,
        total_cost: Decimal.to_float(total_cost),
        run_count: run_count,
        avg_cost: Decimal.to_float(Decimal.div(total_cost, run_count))
      }
    end)
    |> Enum.sort_by(& &1.total_cost, :desc)
  end

  @doc """
  Aggregates recorded prompt-run and suite-run costs by prompt.

  Results are ordered from highest to lowest total cost.
  """
  @spec cost_by_prompt() :: [map()]
  def cost_by_prompt do
    run_costs =
      from(rr in RunResult,
        join: r in assoc(rr, :run),
        join: pv in assoc(r, :prompt_version),
        join: p in assoc(pv, :prompt),
        where: not is_nil(rr.cost_usd),
        group_by: [p.id, p.name],
        select: %{
          prompt_id: p.id,
          prompt_name: p.name,
          total_cost: sum(rr.cost_usd),
          run_count: count(rr.id)
        }
      )
      |> Shared.repo().all()

    suite_costs =
      from(sr in SuiteRun,
        join: pv in assoc(sr, :prompt_version),
        join: p in assoc(pv, :prompt),
        preload: [prompt_version: {pv, prompt: p}]
      )
      |> Shared.repo().all()
      |> Enum.filter(&(Shared.suite_run_cost_entries(&1) > 0))
      |> Enum.map(fn suite_run ->
        %{
          prompt_id: suite_run.prompt_version.prompt.id,
          prompt_name: suite_run.prompt_version.prompt.name,
          total_cost: Shared.suite_run_total_cost(suite_run),
          run_count: 1
        }
      end)

    (run_costs ++ suite_costs)
    |> Enum.group_by(& &1.prompt_id)
    |> Enum.map(fn {_prompt_id, entries} ->
      total_cost = merge_total_cost(entries)
      run_count = Enum.sum(Enum.map(entries, & &1.run_count))

      %{
        prompt_name: List.first(entries).prompt_name,
        total_cost: Decimal.to_float(total_cost),
        run_count: run_count,
        avg_cost: Decimal.to_float(Decimal.div(total_cost, run_count))
      }
    end)
    |> Enum.sort_by(& &1.total_cost, :desc)
  end

  defp merge_total_cost(entries) do
    Enum.reduce(entries, Decimal.new(0), fn entry, acc ->
      Decimal.add(acc, to_decimal(entry.total_cost))
    end)
  end

  defp to_decimal(value) when is_float(value) or is_integer(value),
    do: Decimal.from_float(value / 1)

  defp to_decimal(value), do: value
end
