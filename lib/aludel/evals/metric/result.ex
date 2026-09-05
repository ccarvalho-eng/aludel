defmodule Aludel.Evals.Metric.Result do
  @moduledoc """
  Normalized result returned by every evaluation metric.
  """

  alias Aludel.Evals.Metric.Evaluator

  @enforce_keys [:type, :score, :passed, :reason, :metadata]
  defstruct [:type, :score, :passed, :reason, :metadata, :evaluator]

  @type t :: %__MODULE__{
          type: String.t(),
          score: float(),
          passed: boolean(),
          reason: String.t(),
          metadata: map(),
          evaluator: Evaluator.t() | nil
        }

  @doc """
  Converts a normalized result to the string-keyed persisted result format.

  Optional legacy fields are merged last for compatibility with existing
  assertion consumers.
  """
  @spec to_map(t(), map()) :: map()
  def to_map(%__MODULE__{} = result, legacy_fields \\ %{}) do
    result_map = %{
      "type" => result.type,
      "score" => result.score,
      "passed" => result.passed,
      "reason" => result.reason,
      "metadata" => result.metadata
    }

    result_map
    |> maybe_put_evaluator(result.evaluator)
    |> Map.merge(legacy_fields)
  end

  defp maybe_put_evaluator(result, nil) do
    result
  end

  defp maybe_put_evaluator(result, %Evaluator{} = evaluator) do
    Map.put(result, "evaluator", Evaluator.to_map(evaluator))
  end
end
