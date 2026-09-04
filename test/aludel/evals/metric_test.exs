defmodule Aludel.Evals.MetricTest do
  use ExUnit.Case, async: true

  alias Aludel.Evals.AssertionEvaluator
  alias Aludel.Evals.Metric.Context
  alias Aludel.Evals.Metric.Registry
  alias Aludel.Evals.Metric.Runner

  defmodule RaisingMetric do
    def type do
      "raising"
    end

    def evaluate(_input, _assertion) do
      raise "sensitive evaluator detail"
    end
  end

  defmodule InvalidResultMetric do
    def type do
      "invalid_result"
    end

    def evaluate(_input, _assertion) do
      :invalid
    end
  end

  describe "registry" do
    test "lists the supported metric types in form order" do
      assert Registry.types() == [
               "contains",
               "not_contains",
               "regex",
               "exact_match",
               "json_field",
               "json_deep_compare",
               "rubric_judge"
             ]
    end

    test "resolves every supported type to a metric module" do
      for type <- Registry.types() do
        assert {:ok, module} = Registry.fetch(type)
        assert Code.ensure_loaded?(module)
        assert function_exported?(module, :type, 0)
        assert function_exported?(module, :evaluate, 2)
        assert module.type() == type
      end
    end

    test "evaluates built-in metrics with a contextual input" do
      context =
        Context.new("hello world",
          rendered_input: "Greet Alice",
          variables: %{"name" => "Alice"},
          metadata: %{"language" => "en"}
        )

      assert {:ok, result} =
               Registry.evaluate(context, %{"type" => "contains", "value" => "hello"})

      assert result.passed
      assert result.score == 100.0
      assert result.evaluator.status == :completed
      assert is_number(result.evaluator.duration_ms)
      assert result.evaluator.duration_ms >= 0
    end
  end

  describe "evaluator execution details" do
    test "serializes successful evaluator timing" do
      result =
        AssertionEvaluator.evaluate("hello world", %{
          "type" => "contains",
          "value" => "hello"
        })

      assert %{
               "status" => "completed",
               "duration_ms" => duration_ms
             } = result["evaluator"]

      assert is_number(duration_ms)
      assert duration_ms >= 0
      refute Map.has_key?(result["evaluator"], "error")
    end

    test "marks unsupported evaluators as unavailable" do
      result = AssertionEvaluator.evaluate("output", %{"type" => "missing"})

      assert result["evaluator"] == %{
               "status" => "unavailable",
               "error" => %{
                 "type" => "unsupported_metric",
                 "message" => "Metric type is not registered"
               }
             }
    end

    test "isolates evaluator exceptions without persisting their messages" do
      result = Runner.run(RaisingMetric, "output", %{})

      assert result.passed == false
      assert result.score == 0.0
      assert result.reason == "Metric evaluation failed"
      assert result.evaluator.status == :error

      assert result.evaluator.error == %{
               "type" => "evaluator_exception",
               "message" => "Evaluator raised an exception"
             }

      refute inspect(result) =~ "sensitive evaluator detail"
    end

    test "normalizes invalid evaluator return values" do
      result = Runner.run(InvalidResultMetric, "output", %{})

      assert result.passed == false
      assert result.score == 0.0
      assert result.reason == "Metric returned an invalid result"
      assert result.evaluator.status == :error
      assert result.evaluator.error["type"] == "invalid_result"
    end
  end

  describe "metric context" do
    test "normalizes the output and evaluation evidence" do
      context =
        Context.new("answer",
          expected: "expected answer",
          rendered_input: "question",
          prompt_template: "{{question}}",
          variables: %{"question" => "question"},
          messages: [%{"role" => "user", "content" => "question"}],
          documents: [%{"name" => "guide.txt", "content_type" => "text/plain"}],
          metadata: %{"category" => "support"},
          provider: %{"id" => "provider-id", "model" => "model"},
          prompt_version: %{"id" => "version-id", "version" => 2},
          execution: %{"latency_ms" => 25}
        )

      assert context.output == "answer"
      assert context.expected == "expected answer"
      assert context.rendered_input == "question"
      assert context.prompt_template == "{{question}}"
      assert context.variables == %{"question" => "question"}
      assert context.messages == [%{"role" => "user", "content" => "question"}]
      assert context.documents == [%{"name" => "guide.txt", "content_type" => "text/plain"}]
      assert context.metadata == %{"category" => "support"}
      assert context.provider == %{"id" => "provider-id", "model" => "model"}
      assert context.prompt_version == %{"id" => "version-id", "version" => 2}
      assert context.execution == %{"latency_ms" => 25}
    end

    test "uses safe defaults for optional evidence" do
      assert %Context{
               output: "answer",
               expected: nil,
               rendered_input: nil,
               prompt_template: nil,
               variables: %{},
               messages: [],
               documents: [],
               metadata: %{},
               provider: nil,
               prompt_version: nil,
               execution: %{}
             } = Context.new("answer")
    end

    test "rejects a non-string output" do
      assert_raise ArgumentError, "metric output must be a string", fn ->
        Context.new(nil)
      end
    end

    test "keeps the legacy assertion evaluator API working" do
      legacy =
        AssertionEvaluator.evaluate("hello world", %{
          "type" => "contains",
          "value" => "hello"
        })

      contextual =
        "hello world"
        |> Context.new(metadata: %{"source" => "suite"})
        |> AssertionEvaluator.evaluate(%{"type" => "contains", "value" => "hello"})

      assert Map.delete(contextual, "evaluator") == Map.delete(legacy, "evaluator")
    end
  end

  describe "normalized results" do
    test "preserves legacy string assertion fields" do
      result =
        AssertionEvaluator.evaluate("hello world", %{"type" => "contains", "value" => "hello"})

      assert %{
               "type" => "contains",
               "passed" => true,
               "score" => 100.0,
               "reason" => reason,
               "metadata" => %{},
               "value" => "hello"
             } = result

      assert is_binary(reason)
    end

    test "explains invalid regular expressions" do
      result = AssertionEvaluator.evaluate("hello", %{"type" => "regex", "value" => "["})

      assert %{
               "passed" => false,
               "reason" => "Invalid regular expression",
               "metadata" => %{"valid_pattern" => false}
             } = result

      assert result["score"] == 0.0
    end

    test "normalizes JSON field evidence while preserving actual_value" do
      result =
        AssertionEvaluator.evaluate(~s({"count": 2}), %{
          "type" => "json_field",
          "field" => "count",
          "expected" => 2
        })

      assert %{
               "passed" => true,
               "actual_value" => 2,
               "metadata" => %{
                 "actual_value" => 2,
                 "decoded" => true,
                 "field" => "count"
               }
             } = result
    end

    test "normalizes deep comparison evidence while preserving score_details" do
      result =
        AssertionEvaluator.evaluate(~s({"status":"ok","count":1}), %{
          "type" => "json_deep_compare",
          "expected" => %{"status" => "ok", "count" => 2},
          "threshold" => 50
        })

      assert %{
               "passed" => true,
               "score" => 50.0,
               "score_details" => score_details,
               "metadata" => %{
                 "decoded" => true,
                 "threshold" => 50.0
               }
             } = result

      assert result["metadata"]["score_details"] == score_details
    end

    test "returns a normalized failure for unknown metric types" do
      result =
        AssertionEvaluator.evaluate("output", %{
          "type" => "unknown",
          "value" => "value"
        })

      assert %{
               "type" => "unknown",
               "passed" => false,
               "reason" => "Unsupported metric type",
               "metadata" => %{},
               "value" => "value"
             } = result

      assert result["score"] == 0.0
    end

    test "returns normalized failures for malformed known metrics" do
      assertions = [
        %{"type" => "contains"},
        %{"type" => "not_contains"},
        %{"type" => "regex"},
        %{"type" => "exact_match"},
        %{"type" => "json_field", "field" => "status"},
        %{"type" => "json_deep_compare"}
      ]

      for assertion <- assertions do
        result = AssertionEvaluator.evaluate("null", assertion)

        assert result["type"] == assertion["type"]
        assert result["passed"] == false
        assert result["score"] == 0.0
        assert result["reason"] == "Invalid metric configuration"
        assert result["metadata"] == %{"valid_configuration" => false}
      end
    end

    test "returns normalized JSON decoding failures" do
      json_field =
        AssertionEvaluator.evaluate("not json", %{
          "type" => "json_field",
          "field" => "status",
          "expected" => "ok"
        })

      deep_compare =
        AssertionEvaluator.evaluate("not json", %{
          "type" => "json_deep_compare",
          "expected" => %{"status" => "ok"}
        })

      for result <- [json_field, deep_compare] do
        assert result["passed"] == false
        assert result["score"] == 0.0
        assert result["reason"] == "Output is not valid JSON"
        assert result["metadata"]["decoded"] == false
      end
    end
  end

  describe "score_for_results/1" do
    test "averages numeric scores and rounds to one decimal place" do
      assert AssertionEvaluator.score_for_results([
               %{"score" => 100.0},
               %{"score" => 0.0},
               %{"score" => 33.33}
             ]) == 44.4
    end

    test "ignores nonnumeric scores and handles missing scores" do
      assert AssertionEvaluator.score_for_results([
               %{"score" => 100.0},
               %{"score" => nil},
               %{}
             ]) == 100.0

      assert AssertionEvaluator.score_for_results([%{"score" => nil}, %{}]) == nil
      assert AssertionEvaluator.score_for_results([]) == nil
    end
  end
end
