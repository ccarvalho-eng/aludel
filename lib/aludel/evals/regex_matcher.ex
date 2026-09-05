defmodule Aludel.Evals.RegexMatcher do
  @moduledoc false

  @max_pattern_bytes 4_096
  @max_output_bytes 1_048_576
  @match_limit 100_000
  @match_limit_recursion 10_000
  @timeout_ms 250

  @type limit_reason ::
          :depth_limit | :input_too_large | :match_limit | :pattern_too_large | :timeout
  @type match_error :: limit_reason() | :invalid_pattern | :matcher_exit
  @type option :: {:timeout_ms, non_neg_integer()}

  @spec validate_pattern(term()) :: :ok | {:error, :invalid_pattern | :pattern_too_large}
  def validate_pattern(pattern) do
    case compile(pattern) do
      {:ok, _regex} -> :ok
      {:error, _reason} = error -> error
    end
  end

  @spec match(String.t(), String.t(), [option()]) ::
          {:ok, boolean()} | {:error, match_error()}
  def match(pattern, output, opts \\ [])

  def match(pattern, output, opts) when is_binary(pattern) and is_binary(output) do
    timeout_ms = timeout_ms(opts)

    with {:ok, regex} <- compile(pattern),
         :ok <- validate_output(output) do
      timed_match(regex, output, timeout_ms)
    end
  end

  def match(_pattern, _output, _opts) do
    {:error, :invalid_pattern}
  end

  defp compile(pattern)
       when is_binary(pattern) and byte_size(pattern) <= @max_pattern_bytes do
    case Regex.compile(pattern) do
      {:ok, regex} -> {:ok, regex}
      {:error, _reason} -> {:error, :invalid_pattern}
    end
  end

  defp compile(pattern) when is_binary(pattern) do
    {:error, :pattern_too_large}
  end

  defp compile(_pattern) do
    {:error, :invalid_pattern}
  end

  defp validate_output(output) when byte_size(output) <= @max_output_bytes do
    :ok
  end

  defp validate_output(_output) do
    {:error, :input_too_large}
  end

  defp timeout_ms(opts) do
    case Keyword.get(opts, :timeout_ms, @timeout_ms) do
      timeout_ms when is_integer(timeout_ms) and timeout_ms >= 0 ->
        min(timeout_ms, @timeout_ms)

      _invalid_timeout ->
        @timeout_ms
    end
  end

  defp timed_match(regex, output, timeout_ms) do
    task =
      Task.Supervisor.async_nolink(Aludel.TaskSupervisor, fn ->
        run(regex, output)
      end)

    try do
      case Task.yield(task, timeout_ms) do
        {:ok, result} -> result
        {:exit, _reason} -> {:error, :matcher_exit}
        nil -> {:error, :timeout}
      end
    after
      Task.shutdown(task, :brutal_kill)
    end
  end

  defp run(regex, output) do
    options = [
      {:capture, :none},
      :report_errors,
      {:match_limit, @match_limit},
      {:match_limit_recursion, @match_limit_recursion}
    ]

    case :re.run(output, Regex.re_pattern(regex), options) do
      :match -> {:ok, true}
      :nomatch -> {:ok, false}
      {:error, :match_limit} -> {:error, :match_limit}
      {:error, :match_limit_recursion} -> {:error, :depth_limit}
    end
  end
end
