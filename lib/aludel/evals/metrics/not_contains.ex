defmodule Aludel.Evals.Metrics.NotContains do
  @moduledoc false

  @behaviour Aludel.Evals.Metric

  alias Aludel.Evals.Metric

  @impl true
  def type do
    "not_contains"
  end

  @impl true
  def evaluate(output, %{"value" => value}) do
    Metric.boolean_result(
      type(),
      not String.contains?(output, value),
      "Output excludes disallowed value",
      "Output contains disallowed value"
    )
  end

  def evaluate(_output, _assertion) do
    Metric.invalid_result(type())
  end
end
