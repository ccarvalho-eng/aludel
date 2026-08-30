defmodule Aludel.Evals.Metric.Result do
  @moduledoc """
  Normalized result returned by every evaluation metric.
  """

  @enforce_keys [:type, :score, :passed, :reason, :metadata]
  defstruct [:type, :score, :passed, :reason, :metadata]

  @type t :: %__MODULE__{
          type: String.t(),
          score: float(),
          passed: boolean(),
          reason: String.t(),
          metadata: map()
        }

  @spec to_map(t(), map()) :: map()
  def to_map(%__MODULE__{} = result, legacy_fields \\ %{}) do
    %{
      "type" => result.type,
      "score" => result.score,
      "passed" => result.passed,
      "reason" => result.reason,
      "metadata" => result.metadata
    }
    |> Map.merge(legacy_fields)
  end
end
