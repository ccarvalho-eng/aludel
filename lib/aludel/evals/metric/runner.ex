defmodule Aludel.Evals.Metric.Runner do
  @moduledoc false

  alias Aludel.Evals.Metric.Evaluator
  alias Aludel.Evals.Metric.Result

  @spec run(module(), Aludel.Evals.Metric.input(), map()) :: Result.t()
  def run(module, input, assertion) when is_atom(module) and is_map(assertion) do
    started_at = System.monotonic_time(:microsecond)

    try do
      case module.evaluate(input, assertion) do
        %Result{} = result -> complete(result, elapsed_ms(started_at))
        _other -> invalid_result(metric_type(module, assertion), elapsed_ms(started_at))
      end
    rescue
      _error -> exception_result(metric_type(module, assertion), elapsed_ms(started_at))
    catch
      _kind, _reason -> exit_result(metric_type(module, assertion), elapsed_ms(started_at))
    end
  end

  defp complete(%Result{evaluator: nil} = result, duration_ms) do
    %{result | evaluator: Evaluator.completed(duration_ms)}
  end

  defp complete(%Result{evaluator: evaluator} = result, duration_ms) do
    %{result | evaluator: Evaluator.with_duration(evaluator, duration_ms)}
  end

  defp invalid_result(type, duration_ms) do
    failed_result(
      type,
      "Metric returned an invalid result",
      %{
        "type" => "invalid_result",
        "message" => "Evaluator must return a metric result"
      },
      duration_ms
    )
  end

  defp exception_result(type, duration_ms) do
    failed_result(
      type,
      "Metric evaluation failed",
      %{
        "type" => "evaluator_exception",
        "message" => "Evaluator raised an exception"
      },
      duration_ms
    )
  end

  defp exit_result(type, duration_ms) do
    failed_result(
      type,
      "Metric evaluation failed",
      %{
        "type" => "evaluator_exit",
        "message" => "Evaluator stopped before returning a result"
      },
      duration_ms
    )
  end

  defp failed_result(type, reason, error, duration_ms) do
    %Result{
      type: type,
      passed: false,
      score: 0.0,
      reason: reason,
      metadata: %{},
      evaluator: Evaluator.error(error, duration_ms: duration_ms)
    }
  end

  defp metric_type(module, assertion) do
    Map.get(assertion, "type") || safe_metric_type(module)
  end

  defp safe_metric_type(module) do
    module.type()
  rescue
    _error -> "unknown"
  catch
    _kind, _reason -> "unknown"
  end

  defp elapsed_ms(started_at) do
    elapsed_microseconds = System.monotonic_time(:microsecond) - started_at
    Float.round(elapsed_microseconds / 1_000, 3)
  end
end
