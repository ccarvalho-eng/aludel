defmodule Aludel.Evals.Metric.Registry do
  @moduledoc """
  Registry for the built-in evaluation metrics.

  New metric modules are added here without changing suite execution or result
  aggregation code.
  """

  alias Aludel.Evals.Metric.Context
  alias Aludel.Evals.Metric.Runner
  alias Aludel.Evals.Metrics.Contains
  alias Aludel.Evals.Metrics.ExactMatch
  alias Aludel.Evals.Metrics.JSONDeepCompare
  alias Aludel.Evals.Metrics.JSONField
  alias Aludel.Evals.Metrics.NotContains
  alias Aludel.Evals.Metrics.Regex
  alias Aludel.Evals.Metrics.RubricJudge

  @metrics [
    {"contains", Contains},
    {"not_contains", NotContains},
    {"regex", Regex},
    {"exact_match", ExactMatch},
    {"json_field", JSONField},
    {"json_deep_compare", JSONDeepCompare},
    {"rubric_judge", RubricJudge}
  ]

  @spec types() :: [String.t()]
  def types do
    Enum.map(@metrics, &elem(&1, 0))
  end

  @spec fetch(String.t()) :: {:ok, module()} | :error
  def fetch(type) do
    case List.keyfind(@metrics, type, 0) do
      {_type, module} -> {:ok, module}
      nil -> :error
    end
  end

  @spec evaluate(Context.t() | String.t(), map()) ::
          {:ok, Aludel.Evals.Metric.Result.t()} | :error
  def evaluate(input, %{"type" => type} = assertion) do
    case fetch(type) do
      {:ok, module} -> {:ok, Runner.run(module, input, assertion)}
      :error -> :error
    end
  end

  def evaluate(_input, _assertion) do
    :error
  end
end
