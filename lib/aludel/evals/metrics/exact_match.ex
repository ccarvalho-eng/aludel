defmodule Aludel.Evals.Metrics.ExactMatch do
  @moduledoc false

  @behaviour Aludel.Evals.Metric

  alias Aludel.Evals.Metric

  @impl true
  def type do
    "exact_match"
  end

  @impl true
  def evaluate(input, %{"value" => value}) do
    output = Metric.output(input)

    Metric.boolean_result(
      type(),
      output == value,
      "Output exactly matches expected value",
      "Output does not exactly match expected value"
    )
  end

  def evaluate(_output, _assertion) do
    Metric.invalid_result(type())
  end
end
