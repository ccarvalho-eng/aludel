defmodule Aludel.Evals.Sampling do
  @moduledoc """
  Configuration and deterministic reduction for repeated test case execution.

  Sampling is bounded to protect callers from accidental request amplification.
  Attempts remain ordered and are retained in the aggregate result. The latest
  attempt matching the reduced outcome supplies representative output and
  artifacts, while scores and usage are aggregated across every attempt.
  """

  @max_samples 20
  @reducers [:all, :any, :majority]
  @schema_version 1

  @enforce_keys [:samples, :reducer]
  defstruct samples: 1, reducer: :all, minimum_pass_rate: nil

  @type reducer :: :all | :any | :majority | :minimum_pass_rate
  @type reducer_option :: :all | :any | :majority | {:minimum_pass_rate, number()}
  @type option :: {:samples, pos_integer()} | {:reducer, reducer_option()}

  @type t :: %__MODULE__{
          samples: pos_integer(),
          reducer: reducer(),
          minimum_pass_rate: float() | nil
        }

  @doc """
  Validates sampling options.

  `:samples` defaults to `1` and accepts values up to #{@max_samples}. `:reducer`
  accepts `:all`, `:any`, `:majority`, or `{:minimum_pass_rate, rate}` where the
  rate is between `0.0` and `1.0`.
  """
  @spec new([option()]) :: {:ok, t()} | {:error, {:invalid_sampling, String.t()}}
  def new(opts \\ [])

  def new(opts) when is_list(opts) do
    with :ok <- validate_options(opts),
         {:ok, samples} <- validate_samples(Keyword.get(opts, :samples, 1)),
         {:ok, reducer, minimum_pass_rate} <-
           validate_reducer(Keyword.get(opts, :reducer, :all)) do
      {:ok,
       %__MODULE__{
         samples: samples,
         reducer: reducer,
         minimum_pass_rate: minimum_pass_rate
       }}
    end
  end

  def new(_opts) do
    invalid("options must be a keyword list")
  end

  @doc """
  Restores the sampling configuration stored in a test case result.

  Results created before sampling default to one attempt with the `:all`
  reducer.
  """
  @spec from_result(map()) :: {:ok, t()} | {:error, {:invalid_sampling, String.t()}}
  def from_result(%{"sampling" => %{"schema_version" => 1} = sampling}) do
    with {:ok, reducer} <- persisted_reducer(sampling) do
      new(samples: sampling["samples"], reducer: reducer)
    end
  end

  def from_result(%{"sampling" => _sampling}) do
    invalid("persisted sampling configuration has an unsupported schema")
  end

  def from_result(result) when is_map(result) do
    new()
  end

  @doc """
  Aggregates ordered attempt results according to a validated configuration.

  The aggregate retains every attempt, reports pass-rate evidence, sums token,
  cost, and latency usage, and averages available attempt scores.
  """
  @spec aggregate([map()], t()) :: map()
  def aggregate(attempts, %__MODULE__{samples: samples} = sampling)
      when is_list(attempts) and length(attempts) == samples and samples > 0 do
    attempts =
      attempts
      |> Enum.with_index(1)
      |> Enum.map(fn {attempt, attempt_number} ->
        Map.put(attempt, "attempt", attempt_number)
      end)

    passed_attempts = Enum.count(attempts, &(&1["passed"] == true))
    pass_rate = passed_attempts / samples
    passed = reduced_pass?(sampling, passed_attempts, pass_rate)
    representative = representative_attempt(attempts, passed)

    sampling_metadata =
      sampling_metadata(sampling, passed_attempts, pass_rate, representative["attempt"])

    representative
    |> Map.delete("attempt")
    |> Map.merge(%{
      "passed" => passed,
      "score" => average(attempts, "score"),
      "input_tokens" => total(attempts, "input_tokens"),
      "output_tokens" => total(attempts, "output_tokens"),
      "cost_usd" => total(attempts, "cost_usd"),
      "latency_ms" => total(attempts, "latency_ms"),
      "cost_sample_count" => count(attempts, "cost_usd"),
      "latency_sample_count" => count(attempts, "latency_ms"),
      "sampling" => sampling_metadata,
      "attempts" => attempts
    })
  end

  def aggregate(_attempts, _sampling) do
    raise ArgumentError, "attempt results must match the configured sample count"
  end

  defp validate_options(opts) do
    if Keyword.keyword?(opts) do
      validate_option_names(Keyword.keys(opts) -- [:samples, :reducer])
    else
      invalid("options must be a keyword list")
    end
  end

  defp validate_option_names([]) do
    :ok
  end

  defp validate_option_names(unknown_options) do
    invalid("unknown options: #{Enum.map_join(unknown_options, ", ", &inspect/1)}")
  end

  defp validate_samples(samples)
       when is_integer(samples) and samples >= 1 and samples <= @max_samples do
    {:ok, samples}
  end

  defp validate_samples(_samples) do
    invalid("samples must be an integer between 1 and #{@max_samples}")
  end

  defp validate_reducer(reducer) when reducer in @reducers do
    {:ok, reducer, nil}
  end

  defp validate_reducer({:minimum_pass_rate, rate})
       when is_number(rate) and rate >= 0 and rate <= 1 do
    {:ok, :minimum_pass_rate, rate / 1}
  end

  defp validate_reducer(_reducer) do
    invalid("reducer must be :all, :any, :majority, or {:minimum_pass_rate, rate}")
  end

  defp persisted_reducer(%{
         "reducer" => "minimum_pass_rate",
         "minimum_pass_rate" => rate
       }) do
    {:ok, {:minimum_pass_rate, rate}}
  end

  defp persisted_reducer(%{"reducer" => reducer}) do
    case reducer do
      "all" -> {:ok, :all}
      "any" -> {:ok, :any}
      "majority" -> {:ok, :majority}
      _unknown -> invalid("persisted reducer is invalid")
    end
  end

  defp persisted_reducer(_sampling) do
    invalid("persisted sampling configuration is incomplete")
  end

  defp reduced_pass?(%__MODULE__{reducer: :all, samples: samples}, passed, _rate) do
    passed == samples
  end

  defp reduced_pass?(%__MODULE__{reducer: :any}, passed, _rate) do
    passed > 0
  end

  defp reduced_pass?(%__MODULE__{reducer: :majority, samples: samples}, passed, _rate) do
    passed * 2 > samples
  end

  defp reduced_pass?(%__MODULE__{reducer: :minimum_pass_rate} = sampling, _passed, rate) do
    rate >= sampling.minimum_pass_rate
  end

  defp representative_attempt(attempts, passed) do
    reversed_attempts = Enum.reverse(attempts)

    Enum.find(reversed_attempts, &(&1["passed"] == passed)) || hd(reversed_attempts)
  end

  defp sampling_metadata(sampling, passed_attempts, pass_rate, representative_attempt) do
    %{
      "schema_version" => @schema_version,
      "samples" => sampling.samples,
      "reducer" => Atom.to_string(sampling.reducer),
      "passed_attempts" => passed_attempts,
      "failed_attempts" => sampling.samples - passed_attempts,
      "pass_rate" => Float.round(pass_rate, 4),
      "representative_attempt" => representative_attempt
    }
    |> maybe_put_minimum_pass_rate(sampling.minimum_pass_rate)
  end

  defp maybe_put_minimum_pass_rate(metadata, nil) do
    metadata
  end

  defp maybe_put_minimum_pass_rate(metadata, minimum_pass_rate) do
    Map.put(metadata, "minimum_pass_rate", minimum_pass_rate)
  end

  defp total(attempts, field) do
    case numeric_values(attempts, field) do
      [] -> nil
      values -> Enum.sum(values)
    end
  end

  defp count(attempts, field) do
    attempts
    |> numeric_values(field)
    |> length()
  end

  defp average(attempts, field) do
    case numeric_values(attempts, field) do
      [] ->
        nil

      values ->
        values
        |> then(&(Enum.sum(&1) / length(&1)))
        |> Float.round(1)
    end
  end

  defp numeric_values(attempts, field) do
    attempts
    |> Enum.map(&Map.get(&1, field))
    |> Enum.filter(&is_number/1)
  end

  defp invalid(message) do
    {:error, {:invalid_sampling, message}}
  end
end
