defmodule Aludel.Evals.SamplingTest do
  use ExUnit.Case, async: true

  alias Aludel.Evals.Sampling

  test "applies all, any, and majority reducers" do
    attempts = [attempt(true), attempt(true), attempt(false)]

    assert {:ok, all} = Sampling.new(samples: 3, reducer: :all)
    refute Sampling.aggregate(attempts, all)["passed"]

    assert {:ok, any} = Sampling.new(samples: 3, reducer: :any)
    assert Sampling.aggregate(attempts, any)["passed"]

    assert {:ok, majority} = Sampling.new(samples: 3, reducer: :majority)
    aggregate = Sampling.aggregate(attempts, majority)
    assert aggregate["passed"]
    assert aggregate["score"] == 66.7
    assert aggregate["sampling"]["pass_rate"] == 0.6667
  end

  test "applies a minimum pass-rate reducer without rounding its decision" do
    attempts = [attempt(true), attempt(true), attempt(false)]

    assert {:ok, passing} =
             Sampling.new(samples: 3, reducer: {:minimum_pass_rate, 0.66})

    assert Sampling.aggregate(attempts, passing)["passed"]

    assert {:ok, failing} =
             Sampling.new(samples: 3, reducer: {:minimum_pass_rate, 0.67})

    refute Sampling.aggregate(attempts, failing)["passed"]
  end

  test "rejects unsafe or ambiguous configurations" do
    assert {:error, {:invalid_sampling, _message}} = Sampling.new(samples: 0)
    assert {:error, {:invalid_sampling, _message}} = Sampling.new(samples: 21)
    assert {:error, {:invalid_sampling, _message}} = Sampling.new(reducer: :unknown)

    assert {:error, {:invalid_sampling, _message}} =
             Sampling.new(reducer: {:minimum_pass_rate, 1.1})

    assert {:error, {:invalid_sampling, _message}} = Sampling.new(extra: true)
  end

  test "restores configuration from a persisted aggregate" do
    result = %{
      "sampling" => %{
        "schema_version" => 1,
        "samples" => 4,
        "reducer" => "minimum_pass_rate",
        "minimum_pass_rate" => 0.75
      }
    }

    assert {:ok, sampling} = Sampling.from_result(result)
    assert sampling.samples == 4
    assert sampling.reducer == :minimum_pass_rate
    assert sampling.minimum_pass_rate == 0.75

    assert {:ok, default} = Sampling.from_result(%{})
    assert default.samples == 1
    assert default.reducer == :all

    assert {:error, {:invalid_sampling, _message}} =
             Sampling.from_result(%{"sampling" => %{"schema_version" => 2}})
  end

  defp attempt(passed) do
    %{
      "test_case_id" => "test-case",
      "passed" => passed,
      "score" => if(passed, do: 100.0, else: 0.0),
      "input_tokens" => 5,
      "output_tokens" => 2,
      "cost_usd" => 0.01,
      "latency_ms" => 10,
      "output" => if(passed, do: "pass", else: "fail"),
      "assertion_results" => [],
      "metadata" => %{},
      "artifacts" => %{}
    }
  end
end
