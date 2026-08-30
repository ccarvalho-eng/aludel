defmodule Aludel.Evals.MetricTest do
  use ExUnit.Case, async: true

  alias Aludel.Evals.AssertionEvaluator
  alias Aludel.Evals.Metric.Registry

  describe "registry" do
    test "lists the supported metric types in form order" do
      assert Registry.types() == [
               "contains",
               "not_contains",
               "regex",
               "exact_match",
               "json_field",
               "json_deep_compare"
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
