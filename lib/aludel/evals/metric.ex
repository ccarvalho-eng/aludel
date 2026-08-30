defmodule Aludel.Evals.Metric do
  @moduledoc """
  Contract and shared helpers for evaluation metrics.

  Metrics return a normalized result. Compatibility with historical assertion
  result maps is handled by `Aludel.Evals.AssertionEvaluator`.
  """

  alias Aludel.Evals.Metric.Result

  @default_threshold 100.0

  @callback type() :: String.t()
  @callback evaluate(String.t(), map()) :: Result.t()

  @spec boolean_result(String.t(), boolean(), String.t(), String.t(), map()) :: Result.t()
  def boolean_result(type, passed, success_reason, failure_reason, metadata \\ %{}) do
    %Result{
      type: type,
      passed: passed,
      score: score_from_boolean(passed),
      reason: if(passed, do: success_reason, else: failure_reason),
      metadata: metadata
    }
  end

  @spec decode_json(String.t()) :: {:ok, Jason.decode_value()} | {:error, Jason.DecodeError.t()}
  def decode_json(output) do
    output
    |> String.trim()
    |> String.replace(~r/^```json\s*/i, "")
    |> String.replace(~r/^```\s*/, "")
    |> String.replace(~r/```\s*$/, "")
    |> String.trim()
    |> Jason.decode()
  end

  @spec compare_json_values(term(), term()) :: boolean()
  def compare_json_values(actual, expected) when is_map(actual) or is_list(actual) do
    Jason.encode!(actual) == Jason.encode!(expected)
  end

  def compare_json_values(actual, expected) do
    actual == expected
  end

  @spec normalize_threshold(map()) :: float()
  def normalize_threshold(%{"threshold" => threshold}) when is_integer(threshold) do
    threshold / 1
  end

  def normalize_threshold(%{"threshold" => threshold}) when is_float(threshold) do
    threshold
  end

  def normalize_threshold(_assertion) do
    @default_threshold
  end

  @spec invalid_result(String.t()) :: Result.t()
  def invalid_result(type) do
    %Result{
      type: type,
      passed: false,
      score: 0.0,
      reason: "Invalid metric configuration",
      metadata: %{"valid_configuration" => false}
    }
  end

  defp score_from_boolean(true) do
    100.0
  end

  defp score_from_boolean(false) do
    0.0
  end
end
