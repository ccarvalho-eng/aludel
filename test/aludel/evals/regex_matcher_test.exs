defmodule Aludel.Evals.RegexMatcherTest do
  use ExUnit.Case, async: false

  alias Aludel.Evals.RegexMatcher

  @hostile_pattern "(*LIMIT_MATCH=999999999)(*NO_START_OPT)(*NO_AUTO_POSSESS)(a+)+$"

  test "stops timed-out matcher tasks" do
    output = String.duplicate("a", 10_000) <> "!"

    assert {:error, :timeout} =
             RegexMatcher.match(@hostile_pattern, output, timeout_ms: 0)

    assert Task.Supervisor.children(Aludel.TaskSupervisor) == []
  end

  test "bounds concurrent hostile matches without leaving matcher tasks" do
    output = String.duplicate("a", 10_000) <> "!"

    results =
      1..10
      |> Task.async_stream(
        fn _index -> RegexMatcher.match(@hostile_pattern, output) end,
        max_concurrency: 10,
        ordered: false,
        timeout: 1_000
      )
      |> Enum.to_list()

    assert Enum.all?(results, fn result ->
             result == {:ok, {:error, :match_limit}}
           end)

    assert Task.Supervisor.children(Aludel.TaskSupervisor) == []
  end

  test "accepts outputs and patterns at their size boundaries" do
    pattern = "^" <> String.duplicate("a", 4_094) <> "$"
    output = String.duplicate("a", 1_048_576)

    assert :ok = RegexMatcher.validate_pattern(pattern)
    assert {:ok, true} = RegexMatcher.match("^a+$", output)
  end
end
