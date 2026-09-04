defmodule Aludel.Evals.ReporterTest do
  use ExUnit.Case, async: true

  alias Aludel.Evals.{Report, Reporter, SuiteRun}

  defmodule CustomReporter do
    @behaviour Reporter

    @impl true
    def render(%Report{} = report, options) do
      {:ok, [Keyword.fetch!(options, :prefix), report.status]}
    end
  end

  defmodule InvalidReporter do
    @behaviour Reporter

    @impl true
    def render(%Report{}, _options) do
      :invalid
    end
  end

  describe "normalized reports" do
    test "builds the versioned JSON-compatible report schema" do
      report = Report.from_suite_run(suite_run())

      assert report.schema_version == 2
      assert report.status == "failed"

      assert %{
               "type" => "aludel_eval",
               "schema_version" => 2,
               "summary" => %{
                 "passed" => 1,
                 "failed" => 1,
                 "total" => 2,
                 "pass_rate" => 50.0,
                 "avg_score" => "62.5",
                 "avg_cost_usd" => "0.0042",
                 "avg_latency_ms" => 125,
                 "total_cost_usd" => "0.0084",
                 "cost_sample_count" => 2,
                 "total_latency_ms" => 250,
                 "latency_sample_count" => 2
               },
               "results" => [%{"status" => "passed"}, %{"status" => "failed"}]
             } = Report.to_map(report)
    end

    test "uses a quality policy as the report status" do
      report =
        suite_run(%{
          failed: 1,
          quality_policy_result: %{"status" => "passed", "rules" => []}
        })
        |> Report.from_suite_run()

      assert report.status == "passed"
    end

    test "treats an empty policy-free run as failed" do
      report =
        suite_run(%{passed: 0, failed: 0, results: []})
        |> Report.from_suite_run()

      assert report.status == "failed"
      assert report.summary["pass_rate"] == 0.0
    end
  end

  describe "render/3" do
    test "supports custom reporter modules and normalizes iodata" do
      assert {:ok, "result=failed"} =
               Reporter.render(suite_run(), CustomReporter, prefix: "result=")
    end

    test "rejects unknown reporters" do
      assert {:error, :unknown_reporter} = Reporter.render(suite_run(), :missing)
      assert {:error, :unknown_reporter} = Reporter.render(suite_run(), "json")
    end

    test "rejects invalid custom reporter output" do
      assert {:error, :invalid_reporter_output} =
               Reporter.render(suite_run(), InvalidReporter)
    end
  end

  describe "JSON reporter" do
    test "renders schema version 2 in compact and pretty forms" do
      compact = Reporter.render!(suite_run(), :json)
      pretty = Reporter.render!(suite_run(), :json, pretty: true)

      assert Jason.decode!(compact)["schema_version"] == 2
      assert pretty =~ "\n  \"provider_id\""
    end
  end

  describe "console reporter" do
    test "renders a plain-text summary without model output or control characters" do
      output = Reporter.render!(suite_run(), :console)

      assert output =~ "Aludel evaluation FAILED"
      assert output =~ "Summary: 1 passed, 1 failed, 50.0% pass rate"
      assert output =~ "[PASS] test case case-pass"
      assert output =~ "[FAIL] test case case-fail"
      refute output =~ "unsafe model output"
      refute output =~ "\e"
    end

    test "renders policy status and rule evidence" do
      run =
        suite_run(%{
          quality_policy_result: %{
            "status" => "unavailable",
            "rules" => [
              %{
                "id" => "latency\nrule",
                "status" => "unavailable",
                "reason" => "No latency\rwas recorded"
              }
            ]
          }
        })

      output = Reporter.render!(run, :console)

      assert output =~ "Policy: unavailable"
      assert output =~ "[UNAVAILABLE] latency rule: No latency was recorded"
    end
  end

  describe "JUnit reporter" do
    test "renders valid XML with escaped identifiers, reasons, and model output" do
      run =
        suite_run(%{
          suite_id: "suite<&\"",
          results: [
            result(%{
              "test_case_id" => "case<&\"",
              "passed" => false,
              "output" => "unsafe <output> & \"quote\"\u0000",
              "assertion_results" => [
                %{"passed" => false, "reason" => "expected <safe> & sound"}
              ]
            })
          ],
          passed: 0,
          failed: 1
        })

      xml = Reporter.render!(run, :junit, include_output: true)

      assert xml =~ ~s(tests="1" failures="1")
      assert xml =~ "case&lt;&amp;&quot;"
      assert xml =~ "expected &lt;safe&gt; &amp; sound"
      assert xml =~ "unsafe &lt;output&gt; &amp; &quot;quote&quot;"
      refute xml =~ "\u0000"

      assert {_document, []} = :xmerl_scan.string(String.to_charlist(xml), quiet: true)
    end

    test "omits generated model output by default" do
      xml = Reporter.render!(suite_run(), :junit)

      refute xml =~ "<system-out>"
      refute xml =~ "unsafe model output"
    end

    test "adds a failing policy case when all evaluation cases pass" do
      run =
        suite_run(%{
          results: [result()],
          passed: 1,
          failed: 0,
          quality_policy_result: %{
            "status" => "failed",
            "rules" => [
              %{"id" => "cost", "status" => "failed", "reason" => "Cost exceeded limit"}
            ]
          }
        })

      xml = Reporter.render!(run, :junit)

      assert xml =~ ~s(tests="2" failures="1")
      assert xml =~ ~s(name="quality-policy")
      assert xml =~ "Cost exceeded limit"
    end

    test "represents an empty run as a failure" do
      run = suite_run(%{results: [], passed: 0, failed: 0})

      xml = Reporter.render!(run, :junit)

      assert xml =~ ~s(tests="1" failures="1")
      assert xml =~ ~s(name="evaluation")
      assert xml =~ "No evaluation cases were available"
    end
  end

  describe "GitHub reporter" do
    test "emits a notice for a passing report" do
      run = suite_run(%{results: [result()], passed: 1, failed: 0})

      assert Reporter.render!(run, :github) ==
               "::notice title=Aludel evaluation::Suite run run-123 passed"
    end

    test "escapes workflow commands in untrusted titles and messages" do
      run =
        suite_run(%{
          results: [
            result(%{
              "test_case_id" => "case:one,two",
              "passed" => false,
              "assertion_results" => [
                %{
                  "passed" => false,
                  "reason" => "first line\n::warning::injected%value\r"
                }
              ]
            })
          ],
          passed: 0,
          failed: 1
        })

      output = Reporter.render!(run, :github)

      assert output =~ "title=Test case case%3Aone%2Ctwo"
      assert output =~ "first line%0A::warning::injected%25value%0D"
      refute output =~ "\n"
    end

    test "emits policy errors when case assertions passed" do
      run =
        suite_run(%{
          results: [result()],
          passed: 1,
          failed: 0,
          quality_policy_result: %{
            "status" => "unavailable",
            "rules" => [
              %{
                "id" => "latency",
                "status" => "unavailable",
                "reason" => "No latency was recorded"
              }
            ]
          }
        })

      output = Reporter.render!(run, :github)

      assert output =~ "::error title=Quality policy latency::No latency was recorded"
    end
  end

  defp suite_run(overrides \\ %{}) do
    defaults = %{
      id: "run-123",
      suite_id: "suite-123",
      prompt_version_id: "version-123",
      provider_id: "provider-123",
      passed: 1,
      failed: 1,
      avg_score: Decimal.new("62.5"),
      avg_cost_usd: Decimal.new("0.0042"),
      avg_latency_ms: 125,
      total_cost_usd: Decimal.new("0.0084"),
      cost_sample_count: 2,
      total_latency_ms: 250,
      latency_sample_count: 2,
      quality_policy_result: nil,
      results: [result(), failed_result()]
    }

    struct!(SuiteRun, Map.merge(defaults, overrides))
  end

  defp result(overrides \\ %{}) do
    Map.merge(
      %{
        "test_case_id" => "case-pass",
        "test_case_metadata" => %{"group" => "smoke"},
        "passed" => true,
        "score" => 100.0,
        "output" => "unsafe model output",
        "assertion_results" => [%{"passed" => true, "reason" => "Matched"}],
        "input_tokens" => 4,
        "output_tokens" => 2,
        "cost_usd" => 0.002,
        "latency_ms" => 100
      },
      overrides
    )
  end

  defp failed_result do
    result(%{
      "test_case_id" => "case-fail",
      "passed" => false,
      "score" => 25.0,
      "assertion_results" => [%{"passed" => false, "reason" => "Did not match"}],
      "latency_ms" => 150
    })
  end
end
