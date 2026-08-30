defmodule Aludel.Evals.Metrics.Contains do
  @moduledoc false

  @behaviour Aludel.Evals.Metric

  alias Aludel.Evals.Metric

  @impl true
  def type do
    "contains"
  end

  @impl true
  def evaluate(output, %{"value" => value}) do
    Metric.boolean_result(
      type(),
      String.contains?(output, value),
      "Output contains expected value",
      "Output does not contain expected value"
    )
  end

  def evaluate(_output, _assertion) do
    Metric.invalid_result(type())
  end
end
