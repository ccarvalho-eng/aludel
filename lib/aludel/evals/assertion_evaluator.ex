defmodule Aludel.Evals.AssertionEvaluator do
  @moduledoc """
  Backward-compatible facade for behaviour-driven evaluation metrics.
  """

  alias Aludel.Evals.Metric.Registry
  alias Aludel.Evals.Metric.Result

  @spec evaluate(String.t(), map()) :: map()
  def evaluate(output, assertion) do
    case Registry.evaluate(output, assertion) do
      {:ok, result} ->
        Result.to_map(result, legacy_fields(result, assertion))

      :error ->
        unsupported_result(assertion)
    end
  end

  @spec score_for_results([map()]) :: float() | nil
  def score_for_results([]) do
    nil
  end

  def score_for_results(results) do
    scores =
      results
      |> Enum.map(&Map.get(&1, "score"))
      |> Enum.filter(&is_number/1)

    if scores == [] do
      nil
    else
      Float.round(Enum.sum(scores) / length(scores), 1)
    end
  end

  defp legacy_fields(%Result{type: type}, assertion)
       when type in ["contains", "not_contains", "regex", "exact_match"] do
    %{"value" => assertion["value"]}
  end

  defp legacy_fields(
         %Result{metadata: %{"valid_configuration" => false}},
         assertion
       ) do
    %{"value" => Map.get(assertion, "value")}
  end

  defp legacy_fields(%Result{type: "json_field", metadata: metadata}, assertion) do
    %{
      "value" => %{
        "field" => assertion["field"],
        "expected" => assertion["expected"]
      },
      "actual_value" => metadata["actual_value"]
    }
  end

  defp legacy_fields(%Result{type: "json_deep_compare", metadata: metadata}, assertion) do
    %{
      "value" => %{
        "expected" => assertion["expected"],
        "threshold" => metadata["threshold"]
      },
      "score_details" => metadata["score_details"]
    }
  end

  defp legacy_fields(_result, assertion) do
    %{"value" => Map.get(assertion, "value")}
  end

  defp unsupported_result(assertion) do
    %Result{
      type: Map.get(assertion, "type"),
      passed: false,
      score: 0.0,
      reason: "Unsupported metric type",
      metadata: %{}
    }
    |> Result.to_map(%{"value" => Map.get(assertion, "value")})
  end
end
