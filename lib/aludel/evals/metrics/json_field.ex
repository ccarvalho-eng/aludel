defmodule Aludel.Evals.Metrics.JSONField do
  @moduledoc false

  @behaviour Aludel.Evals.Metric

  alias Aludel.Evals.Metric
  alias Aludel.Evals.Metric.Result

  @impl true
  def type do
    "json_field"
  end

  @impl true
  def evaluate(output, %{"field" => field, "expected" => expected}) do
    case Metric.decode_json(output) do
      {:ok, json} ->
        actual_value = get_in(json, String.split(field, "."))
        passed = Metric.compare_json_values(actual_value, expected)

        Metric.boolean_result(
          type(),
          passed,
          "JSON field matches expected value",
          "JSON field does not match expected value",
          %{
            "actual_value" => actual_value,
            "decoded" => true,
            "field" => field
          }
        )

      {:error, _reason} ->
        %Result{
          type: type(),
          passed: false,
          score: 0.0,
          reason: "Output is not valid JSON",
          metadata: %{
            "actual_value" => nil,
            "decoded" => false,
            "field" => field
          }
        }
    end
  end

  def evaluate(_output, _assertion) do
    Metric.invalid_result(type())
  end
end
