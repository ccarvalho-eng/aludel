defmodule Aludel.Evals.Metrics.Regex do
  @moduledoc false

  @behaviour Aludel.Evals.Metric

  alias Aludel.Evals.Metric
  alias Aludel.Evals.Metric.Evaluator
  alias Aludel.Evals.Metric.Result
  alias Aludel.Evals.RegexMatcher

  @impl true
  def type do
    "regex"
  end

  @impl true
  def evaluate(input, %{"value" => pattern}) when is_binary(pattern) do
    output = Metric.output(input)

    case RegexMatcher.match(pattern, output) do
      {:ok, matched?} ->
        result(matched?)

      {:error, :pattern_too_large} ->
        resource_limited_result(
          "Regular expression pattern exceeds 4096 bytes",
          "pattern_size"
        )

      {:error, :invalid_pattern} ->
        failed_result("Invalid regular expression", %{"valid_pattern" => false})

      {:error, :input_too_large} ->
        resource_limited_result(
          "Regular expression evaluation exceeded resource limits",
          "input_size"
        )

      {:error, reason} when reason in [:depth_limit, :match_limit, :timeout] ->
        resource_limited_result(
          "Regular expression evaluation exceeded resource limits",
          Atom.to_string(reason)
        )

      {:error, :matcher_exit} ->
        resource_limited_result(
          "Regular expression evaluation failed",
          "matcher_exit"
        )
    end
  end

  def evaluate(_output, _assertion) do
    Metric.invalid_result(type())
  end

  defp result(matched?) do
    Metric.boolean_result(
      type(),
      matched?,
      "Output matches regular expression",
      "Output does not match regular expression",
      %{"valid_pattern" => true}
    )
  end

  defp resource_limited_result(reason, limit) do
    %Result{
      type: type(),
      passed: false,
      score: 0.0,
      reason: reason,
      metadata: %{
        "limit_exceeded" => limit,
        "valid_pattern" => limit != "pattern_size"
      },
      evaluator:
        Evaluator.error(%{
          "type" => "regex_resource_limit",
          "message" => "Regular expression evaluation exceeded configured limits"
        })
    }
  end

  defp failed_result(reason, metadata) do
    Metric.boolean_result(
      type(),
      false,
      "Output matches regular expression",
      reason,
      metadata
    )
  end
end
