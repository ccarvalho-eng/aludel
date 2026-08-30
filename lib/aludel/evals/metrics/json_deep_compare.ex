defmodule Aludel.Evals.Metrics.JSONDeepCompare do
  @moduledoc false

  @behaviour Aludel.Evals.Metric

  alias Aludel.Evals.DeepCompare
  alias Aludel.Evals.Metric
  alias Aludel.Evals.Metric.Result

  @empty_score_details %{
    "matches" => 0,
    "total" => 0,
    "field_scores" => %{},
    "comparisons" => %{}
  }

  @impl true
  def type do
    "json_deep_compare"
  end

  @impl true
  def evaluate(output, %{"expected" => _expected} = assertion) do
    threshold = Metric.normalize_threshold(assertion)

    case Metric.decode_json(output) do
      {:ok, json} ->
        score_details = DeepCompare.compare(json, assertion["expected"])
        score = DeepCompare.score(score_details)
        passed = score >= threshold

        %Result{
          type: type(),
          passed: passed,
          score: score,
          reason: comparison_reason(passed, threshold),
          metadata: %{
            "decoded" => true,
            "score_details" => score_details,
            "threshold" => threshold
          }
        }

      {:error, _reason} ->
        %Result{
          type: type(),
          passed: false,
          score: 0.0,
          reason: "Output is not valid JSON",
          metadata: %{
            "decoded" => false,
            "score_details" => @empty_score_details,
            "threshold" => threshold
          }
        }
    end
  end

  def evaluate(_output, _assertion) do
    Metric.invalid_result(type())
  end

  defp comparison_reason(true, threshold) do
    "Deep comparison meets the #{threshold}% threshold"
  end

  defp comparison_reason(false, threshold) do
    "Deep comparison is below the #{threshold}% threshold"
  end
end
