defmodule Aludel.Evals.QualityPolicyTest do
  use ExUnit.Case, async: true

  alias Aludel.Evals.QualityPolicy

  describe "evaluate/3" do
    test "evaluates pass rate, metadata groups, metric scores, cost, and latency" do
      policy = %{
        "schema_version" => 1,
        "rules" => [
          %{"id" => "overall", "type" => "overall_pass_rate", "minimum" => 0.5},
          %{
            "id" => "priority",
            "type" => "metadata_pass_rate",
            "metadata" => %{"priority" => "high"},
            "minimum" => 1.0
          },
          %{
            "id" => "judge",
            "type" => "evaluator_score",
            "metric" => "rubric_judge",
            "minimum" => 80
          },
          %{"id" => "cost", "type" => "total_cost_usd", "maximum" => 0.3},
          %{"id" => "latency", "type" => "average_latency_ms", "maximum" => 150}
        ]
      }

      results = [
        result(true, %{"priority" => "high"}, 90.0),
        result(false, %{"priority" => "low"}, 70.0)
      ]

      summary = %{total_cost_usd: Decimal.new("0.30"), avg_latency_ms: 150}

      assert %{
               "schema_version" => 1,
               "status" => "passed",
               "passed" => true,
               "rules" => rules
             } = QualityPolicy.evaluate(policy, results, summary)

      assert Enum.map(rules, & &1["status"]) == List.duplicate("passed", 5)
      assert rule(rules, "overall")["actual"] == 0.5
      assert rule(rules, "overall")["sample_count"] == 2
      assert rule(rules, "priority")["actual"] == 1.0
      assert rule(rules, "priority")["sample_count"] == 1
      assert rule(rules, "judge")["actual"] == 80.0
      assert rule(rules, "judge")["sample_count"] == 2
      assert rule(rules, "cost")["actual"] == 0.3
      assert rule(rules, "latency")["actual"] == 150
    end

    test "reports failed rules without treating them as evaluator failures" do
      policy = %{
        "schema_version" => 1,
        "rules" => [
          %{"id" => "overall", "type" => "overall_pass_rate", "minimum" => 0.75}
        ]
      }

      result = QualityPolicy.evaluate(policy, [result(true), result(false)], %{})

      assert result["status"] == "failed"
      refute result["passed"]
      assert [rule] = result["rules"]
      assert rule["status"] == "failed"
      assert rule["actual"] == 0.5
    end

    test "uses unrounded values for threshold decisions" do
      pass_rate_policy = %{
        "schema_version" => 1,
        "rules" => [
          %{"id" => "rate", "type" => "overall_pass_rate", "minimum" => 0.6667}
        ]
      }

      rate_result =
        QualityPolicy.evaluate(
          pass_rate_policy,
          [result(true), result(true), result(false)],
          %{}
        )

      assert rate_result["status"] == "failed"
      assert hd(rate_result["rules"])["actual"] == 0.6667

      score_policy = %{
        "schema_version" => 1,
        "rules" => [
          %{
            "id" => "score",
            "type" => "evaluator_score",
            "metric" => "rubric_judge",
            "minimum" => 83.33
          }
        ]
      }

      score_result =
        QualityPolicy.evaluate(
          score_policy,
          [result(true, %{}, 80.0), result(true, %{}, 86.68)],
          %{}
        )

      assert score_result["status"] == "passed"
      assert hd(score_result["rules"])["actual"] == 83.3
    end

    test "reports unavailable evidence explicitly" do
      policy = %{
        "schema_version" => 1,
        "rules" => [
          %{
            "id" => "missing_group",
            "type" => "metadata_pass_rate",
            "metadata" => %{"priority" => "missing"},
            "minimum" => 1.0
          },
          %{
            "id" => "missing_metric",
            "type" => "evaluator_score",
            "metric" => "rubric_judge",
            "minimum" => 80
          },
          %{"id" => "missing_cost", "type" => "total_cost_usd", "maximum" => 1.0},
          %{
            "id" => "missing_latency",
            "type" => "average_latency_ms",
            "maximum" => 1_000
          }
        ]
      }

      result = QualityPolicy.evaluate(policy, [result(true)], %{})

      assert result["status"] == "unavailable"
      refute result["passed"]
      assert Enum.all?(result["rules"], &(&1["status"] == "unavailable"))
      assert Enum.all?(result["rules"], &is_binary(&1["reason"]))
    end

    test "averages evaluator scores across every repeated attempt" do
      policy = %{
        "schema_version" => 1,
        "rules" => [
          %{
            "id" => "judge",
            "type" => "evaluator_score",
            "metric" => "rubric_judge",
            "minimum" => 80
          }
        ]
      }

      sampled_result = %{
        "passed" => true,
        "test_case_metadata" => %{},
        "attempts" => [result(true, %{}, 70.0), result(true, %{}, 90.0)]
      }

      result = QualityPolicy.evaluate(policy, [sampled_result], %{})

      assert result["status"] == "passed"
      assert [rule] = result["rules"]
      assert rule["actual"] == 80.0
      assert rule["sample_count"] == 2
    end

    test "returns an invalid outcome for malformed definitions" do
      policy = %{
        "schema_version" => 1,
        "rules" => [
          %{"id" => "duplicate", "type" => "overall_pass_rate", "minimum" => 1.1},
          %{"id" => "duplicate", "type" => "unknown"}
        ]
      }

      assert %{
               "schema_version" => 1,
               "status" => "invalid",
               "passed" => false,
               "rules" => [],
               "errors" => errors
             } = QualityPolicy.evaluate(policy, [], %{})

      assert length(errors) >= 3
      assert Enum.all?(errors, &is_binary/1)
    end

    test "reports overall pass rate as unavailable for an empty result set" do
      policy = %{
        "schema_version" => 1,
        "rules" => [
          %{"id" => "overall", "type" => "overall_pass_rate", "minimum" => 1.0}
        ]
      }

      result = QualityPolicy.evaluate(policy, [], %{})

      assert result["status"] == "unavailable"
      assert [rule] = result["rules"]
      assert rule["reason"] == "No test case results were available"
    end
  end

  describe "validate/1" do
    test "accepts a bounded version-one policy" do
      assert :ok =
               QualityPolicy.validate(%{
                 "schema_version" => 1,
                 "rules" => [
                   %{"id" => "overall", "type" => "overall_pass_rate", "minimum" => 0.9}
                 ]
               })
    end

    test "rejects unsupported schemas and empty rule sets" do
      assert {:error, errors} =
               QualityPolicy.validate(%{"schema_version" => 2, "rules" => []})

      assert "schema_version must be 1" in errors
      assert "rules must contain between 1 and 50 entries" in errors
    end

    test "rejects unknown fields and non-JSON policy data" do
      assert {:error, unknown_errors} =
               QualityPolicy.validate(%{
                 "label" => "typo",
                 "schema_version" => 1,
                 "rules" => [
                   %{
                     "id" => "overall",
                     "type" => "overall_pass_rate",
                     "minimum" => 0.9,
                     "mininum" => 0.8
                   }
                 ]
               })

      assert "rules[0] contains unsupported fields" in unknown_errors
      assert "policy contains unsupported fields" in unknown_errors

      assert {:error, json_errors} =
               QualityPolicy.validate(%{
                 "schema_version" => 1,
                 "rules" => [
                   %{
                     "id" => "group",
                     "type" => "metadata_pass_rate",
                     "minimum" => 1.0,
                     "metadata" => %{"owner" => self()}
                   }
                 ]
               })

      assert "policy must contain only JSON-compatible values" in json_errors
    end
  end

  defp result(passed, metadata \\ %{}, score \\ nil) do
    assertion_results =
      if is_number(score) do
        [%{"type" => "rubric_judge", "score" => score, "passed" => passed}]
      else
        []
      end

    %{
      "passed" => passed,
      "test_case_metadata" => metadata,
      "assertion_results" => assertion_results
    }
  end

  defp rule(rules, id) do
    Enum.find(rules, &(&1["id"] == id))
  end
end
