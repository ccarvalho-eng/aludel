defmodule Aludel.Prompts.Optimization do
  @moduledoc """
  Multi-objective prompt analysis inspired by GEPA's Pareto selection.
  """

  @required_metrics [:avg_pass_rate, :cost_per_passed_test, :latency_per_passed_test]

  @spec analyze([map()]) :: %{candidates: [map()], frontier: [map()]}
  def analyze(metrics) do
    candidates = Enum.map(metrics, &annotate_candidate(&1, metrics))

    %{
      candidates: candidates,
      frontier: Enum.filter(candidates, &(&1.pareto_status == :frontier))
    }
  end

  defp annotate_candidate(candidate, metrics) do
    status =
      cond do
        not eligible?(candidate) ->
          :insufficient

        Enum.any?(metrics, &dominates?(&1, candidate)) ->
          :dominated

        true ->
          :frontier
      end

    Map.put(candidate, :pareto_status, status)
  end

  defp eligible?(candidate) do
    Enum.all?(@required_metrics, &is_number(Map.get(candidate, &1)))
  end

  defp dominates?(challenger, candidate) do
    eligible?(challenger) and challenger != candidate and
      no_worse?(challenger, candidate) and strictly_better?(challenger, candidate)
  end

  defp no_worse?(challenger, candidate) do
    challenger.avg_pass_rate >= candidate.avg_pass_rate and
      challenger.cost_per_passed_test <= candidate.cost_per_passed_test and
      challenger.latency_per_passed_test <= candidate.latency_per_passed_test
  end

  defp strictly_better?(challenger, candidate) do
    challenger.avg_pass_rate > candidate.avg_pass_rate or
      challenger.cost_per_passed_test < candidate.cost_per_passed_test or
      challenger.latency_per_passed_test < candidate.latency_per_passed_test
  end
end
