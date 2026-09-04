defmodule Aludel.Evals.Metric.Evaluator do
  @moduledoc """
  Normalized execution details for the evaluator behind a metric result.

  Deterministic metrics usually record only status and duration. Model-backed
  evaluators can also attribute provider, model, token usage, and cost without
  mixing that usage with the model output being evaluated.
  """

  @statuses [:completed, :error, :unavailable]

  @enforce_keys [:status]
  defstruct status: nil,
            duration_ms: nil,
            provider: nil,
            model: nil,
            input_tokens: nil,
            output_tokens: nil,
            cost_usd: nil,
            error: nil

  @type status :: :completed | :error | :unavailable

  @type t :: %__MODULE__{
          status: status(),
          duration_ms: number() | nil,
          provider: String.t() | nil,
          model: String.t() | nil,
          input_tokens: non_neg_integer() | nil,
          output_tokens: non_neg_integer() | nil,
          cost_usd: number() | nil,
          error: map() | nil
        }

  @doc """
  Creates evaluator details and validates the lifecycle status.
  """
  @spec new(status(), keyword()) :: t()
  def new(status, attrs \\ []) when status in @statuses and is_list(attrs) do
    struct!(__MODULE__, Keyword.put(attrs, :status, status))
  end

  @doc """
  Records a successfully completed evaluator.
  """
  @spec completed(number(), keyword()) :: t()
  def completed(duration_ms, attrs \\ []) when is_number(duration_ms) and duration_ms >= 0 do
    new(:completed, Keyword.put(attrs, :duration_ms, duration_ms))
  end

  @doc """
  Records an evaluator infrastructure failure.
  """
  @spec error(map(), keyword()) :: t()
  def error(error, attrs \\ []) when is_map(error) and is_list(attrs) do
    new(:error, Keyword.put(attrs, :error, error))
  end

  @doc """
  Records an evaluator that could not be resolved or used.
  """
  @spec unavailable(map()) :: t()
  def unavailable(error) when is_map(error) do
    new(:unavailable, error: error)
  end

  @doc """
  Adds measured duration when the evaluator did not provide its own timing.
  """
  @spec with_duration(t(), number()) :: t()
  def with_duration(%__MODULE__{duration_ms: nil} = evaluator, duration_ms)
      when is_number(duration_ms) and duration_ms >= 0 do
    %{evaluator | duration_ms: duration_ms}
  end

  def with_duration(%__MODULE__{} = evaluator, _duration_ms) do
    evaluator
  end

  @doc """
  Converts evaluator details to a JSON-compatible map, omitting absent values.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = evaluator) do
    %{"status" => Atom.to_string(evaluator.status)}
    |> put_if_present("duration_ms", evaluator.duration_ms)
    |> put_if_present("provider", evaluator.provider)
    |> put_if_present("model", evaluator.model)
    |> put_if_present("input_tokens", evaluator.input_tokens)
    |> put_if_present("output_tokens", evaluator.output_tokens)
    |> put_if_present("cost_usd", evaluator.cost_usd)
    |> put_if_present("error", evaluator.error)
  end

  defp put_if_present(map, _key, nil) do
    map
  end

  defp put_if_present(map, key, value) do
    Map.put(map, key, value)
  end
end
