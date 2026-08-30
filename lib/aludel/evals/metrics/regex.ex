defmodule Aludel.Evals.Metrics.Regex do
  @moduledoc false

  @behaviour Aludel.Evals.Metric

  alias Aludel.Evals.Metric

  @impl true
  def type do
    "regex"
  end

  @impl true
  def evaluate(output, %{"value" => pattern}) do
    case Regex.compile(pattern) do
      {:ok, regex} ->
        Metric.boolean_result(
          type(),
          Regex.match?(regex, output),
          "Output matches regular expression",
          "Output does not match regular expression",
          %{"valid_pattern" => true}
        )

      {:error, _reason} ->
        Metric.boolean_result(
          type(),
          false,
          "Output matches regular expression",
          "Invalid regular expression",
          %{"valid_pattern" => false}
        )
    end
  end

  def evaluate(_output, _assertion) do
    Metric.invalid_result(type())
  end
end
