defmodule Aludel.Web.ExportControllerTest do
  use Aludel.Web.ConnCase, async: true

  import Aludel.EvalsFixtures
  import Aludel.PromptsFixtures
  import Aludel.ProvidersFixtures
  import Aludel.RunsFixtures

  describe "GET /runs/results/:id/export" do
    test "downloads a run result payload as JSON", %{conn: conn} do
      run = run_fixture(%{name: "Export Run"})
      provider = provider_fixture(%{name: "Export Provider"})

      result =
        run_result_fixture(%{
          run_id: run.id,
          provider_id: provider.id,
          output: "Callback output",
          status: :completed,
          input_tokens: nil,
          output_tokens: nil,
          latency_ms: nil,
          cost_usd: nil,
          metadata: %{"trace_id" => "trace-123"},
          artifacts: %{
            "schema_version" => 1,
            "steps" => [%{"index" => 0, "mode" => "callback", "status" => "completed"}]
          }
        })

      conn = get(conn, "/runs/results/#{result.id}/export")

      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/json"
      assert get_resp_header(conn, "cache-control") == ["no-store, max-age=0"]
      assert get_resp_header(conn, "pragma") == ["no-cache"]
      assert get_resp_header(conn, "expires") == ["0"]

      assert get_resp_header(conn, "content-disposition") == [
               "attachment; filename=\"run-result-#{result.id}.json\""
             ]

      payload = Jason.decode!(conn.resp_body)

      assert payload["type"] == "run_result"
      assert payload["run"]["id"] == run.id
      assert payload["run"]["name"] == "Export Run"
      assert payload["result"]["id"] == result.id
      assert payload["result"]["provider"]["id"] == provider.id
      assert payload["result"]["provider"]["name"] == "Export Provider"
      assert payload["result"]["status"] == "completed"
      assert payload["result"]["output"] == "Callback output"
      assert payload["result"]["metadata"]["trace_id"] == "trace-123"
      assert payload["result"]["artifacts"]["schema_version"] == 1
    end
  end

  describe "GET /suites/runs/:id/export" do
    test "downloads a suite run payload as JSON", %{conn: conn} do
      prompt = prompt_fixture_with_version(%{name: "Export Prompt"})
      prompt = Aludel.Prompts.get_prompt_with_versions!(prompt.id)
      version = hd(prompt.versions)
      suite = suite_fixture(%{name: "Export Suite", prompt_id: prompt.id})
      provider = provider_fixture(%{name: "Suite Provider"})
      test_case = test_case_fixture(%{suite_id: suite.id})

      {:ok, suite_policy} =
        Aludel.Evals.create_suite_policy(suite, %{
          "schema_version" => 1,
          "rules" => [
            %{"id" => "overall", "type" => "overall_pass_rate", "minimum" => 0.9}
          ]
        })

      policy_result = %{
        "schema_version" => 1,
        "policy_id" => suite_policy.id,
        "policy_version" => 1,
        "status" => "passed",
        "passed" => true,
        "rules" => []
      }

      suite_run =
        suite_run_fixture(%{
          suite_id: suite.id,
          prompt_version_id: version.id,
          provider_id: provider.id,
          passed: 1,
          failed: 0,
          avg_cost_usd: Decimal.new("0.0010"),
          avg_latency_ms: 250,
          avg_score: Decimal.new("75.0"),
          suite_policy_id: suite_policy.id,
          quality_policy_result: policy_result,
          results: [
            %{
              "test_case_id" => test_case.id,
              "test_case_metadata" => %{"priority" => "high"},
              "passed" => true,
              "score" => 75.0,
              "output" => "Structured output",
              "input_tokens" => 14,
              "output_tokens" => 7,
              "assertion_results" => [
                %{
                  "type" => "json_deep_compare",
                  "passed" => true,
                  "score" => 75.0,
                  "reason" => "Deep comparison meets the 70.0% threshold",
                  "metadata" => %{
                    "decoded" => true,
                    "threshold" => 70.0
                  },
                  "value" => %{
                    "expected" => %{
                      "status" => "ok",
                      "count" => 2,
                      "meta" => %{"city" => "NYC", "zip" => "10001"}
                    },
                    "threshold" => 70.0
                  },
                  "score_details" => %{
                    "matches" => 3,
                    "total" => 4,
                    "field_scores" => %{
                      "status" => 1,
                      "count" => 0,
                      "meta.city" => 1,
                      "meta.zip" => 1
                    }
                  }
                }
              ],
              "cost_usd" => 0.001,
              "latency_ms" => 250,
              "metadata" => %{"trace_id" => "suite-export-trace"},
              "artifacts" => %{
                "schema_version" => 1,
                "steps" => [%{"index" => 0, "mode" => "callback", "status" => "completed"}]
              },
              "retry_count" => 1,
              "retried_at" => "2026-04-26T13:00:00Z"
            }
          ]
        })

      conn = get(conn, "/suites/runs/#{suite_run.id}/export")

      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/json"
      assert get_resp_header(conn, "cache-control") == ["no-store, max-age=0"]
      assert get_resp_header(conn, "pragma") == ["no-cache"]
      assert get_resp_header(conn, "expires") == ["0"]

      assert get_resp_header(conn, "content-disposition") == [
               "attachment; filename=\"suite-run-#{suite_run.id}.json\""
             ]

      payload = Jason.decode!(conn.resp_body)

      assert payload["type"] == "suite_run"
      assert payload["suite_run"]["id"] == suite_run.id
      assert payload["suite_run"]["suite"]["id"] == suite.id
      assert payload["suite_run"]["suite"]["name"] == "Export Suite"
      assert payload["suite_run"]["provider"]["id"] == provider.id
      assert payload["suite_run"]["provider"]["name"] == "Suite Provider"
      assert payload["suite_run"]["summary"]["passed"] == 1
      assert payload["suite_run"]["summary"]["failed"] == 0
      assert payload["suite_run"]["summary"]["avg_cost_usd"] == 0.001
      assert payload["suite_run"]["summary"]["avg_score"] == 75.0

      assert payload["suite_run"]["quality_policy"] == %{
               "id" => suite_policy.id,
               "version" => 1,
               "definition" => suite_policy.definition,
               "result" => policy_result
             }

      assert payload["suite_run"]["results"] == [
               %{
                 "assertion_results" => [
                   %{
                     "passed" => true,
                     "score" => 75.0,
                     "reason" => "Deep comparison meets the 70.0% threshold",
                     "metadata" => %{
                       "decoded" => true,
                       "threshold" => 70.0
                     },
                     "score_details" => %{
                       "field_scores" => %{
                         "count" => 0,
                         "meta.city" => 1,
                         "meta.zip" => 1,
                         "status" => 1
                       },
                       "matches" => 3,
                       "total" => 4
                     },
                     "type" => "json_deep_compare",
                     "value" => %{
                       "expected" => %{
                         "count" => 2,
                         "meta" => %{"city" => "NYC", "zip" => "10001"},
                         "status" => "ok"
                       },
                       "threshold" => 70.0
                     }
                   }
                 ],
                 "artifacts" => %{
                   "schema_version" => 1,
                   "steps" => [
                     %{"index" => 0, "mode" => "callback", "status" => "completed"}
                   ]
                 },
                 "cost_usd" => 0.001,
                 "error" => nil,
                 "input_tokens" => 14,
                 "latency_ms" => 250,
                 "metadata" => %{"trace_id" => "suite-export-trace"},
                 "output" => "Structured output",
                 "output_tokens" => 7,
                 "passed" => true,
                 "score" => 75.0,
                 "retry_count" => 1,
                 "retried_at" => "2026-04-26T13:00:00Z",
                 "status" => "passed",
                 "test_case_id" => test_case.id,
                 "test_case_metadata" => %{"priority" => "high"}
               }
             ]
    end
  end

  describe "GET /suites/runs/:id/report/:format" do
    test "downloads each built-in evaluation report with safe response headers", %{conn: conn} do
      suite_run = suite_run_fixture(%{passed: 1, failed: 0, results: []})

      formats = [
        {"console", "text/plain", ".txt", "Aludel evaluation"},
        {"json", "application/json", ".json", ~s("schema_version": 2)},
        {"junit", "application/xml", ".xml", "<testsuites"},
        {"github", "text/plain", ".txt", "::notice title=Aludel evaluation"}
      ]

      Enum.each(formats, fn {format, content_type, extension, expected} ->
        response = get(recycle(conn), "/suites/runs/#{suite_run.id}/report/#{format}")

        assert response.status == 200
        assert response.resp_body =~ expected
        assert List.first(get_resp_header(response, "content-type")) =~ content_type
        assert get_resp_header(response, "cache-control") == ["no-store, max-age=0"]

        assert get_resp_header(response, "content-disposition") == [
                 "attachment; filename=\"evaluation-report-#{suite_run.id}#{extension}\""
               ]
      end)
    end

    test "includes generated output in JUnit only after explicit opt-in", %{conn: conn} do
      output = "Generated response"

      suite_run =
        suite_run_fixture(%{
          passed: 1,
          failed: 0,
          results: [
            %{
              "test_case_id" => Ecto.UUID.generate(),
              "passed" => true,
              "output" => output,
              "assertion_results" => []
            }
          ]
        })

      default_response = get(conn, "/suites/runs/#{suite_run.id}/report/junit")
      refute default_response.resp_body =~ output

      opted_in_response =
        get(recycle(conn), "/suites/runs/#{suite_run.id}/report/junit?include_output=true")

      assert opted_in_response.resp_body =~ output
    end

    test "rejects unsupported report formats without resolving arbitrary modules", %{conn: conn} do
      suite_run = suite_run_fixture()

      response = get(conn, "/suites/runs/#{suite_run.id}/report/Elixir.System")

      assert response.status == 400
      assert response.resp_body == "Unsupported report format"
    end
  end

  describe "GET /prompts/:id/evolution/export/:format" do
    test "downloads evolution metrics as JSON", %{conn: conn} do
      prompt = prompt_fixture_with_version(%{name: "Evolution Export Prompt"})
      prompt = Aludel.Prompts.get_prompt_with_versions!(prompt.id)
      version = hd(prompt.versions)
      suite = suite_fixture(%{name: "Evolution Suite", prompt_id: prompt.id})
      provider = provider_fixture(%{name: "Evolution Provider"})

      _suite_run =
        suite_run_fixture(%{
          suite_id: suite.id,
          prompt_version_id: version.id,
          provider_id: provider.id,
          passed: 5,
          failed: 1,
          avg_cost_usd: Decimal.new("0.0015"),
          avg_latency_ms: 300,
          avg_score: Decimal.new("80.5")
        })

      conn = get(conn, "/prompts/#{prompt.id}/evolution/export/json")

      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/json"
      assert get_resp_header(conn, "cache-control") == ["no-store, max-age=0"]
      assert get_resp_header(conn, "pragma") == ["no-cache"]
      assert get_resp_header(conn, "expires") == ["0"]

      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ ~r/attachment; filename="prompt-evolution-.*\.json"/

      payload = Jason.decode!(conn.resp_body)

      assert payload["type"] == "prompt_evolution"
      assert payload["prompt"]["id"] == prompt.id
      assert payload["prompt"]["name"] == "Evolution Export Prompt"
      assert is_list(payload["metrics"])

      [metric] = payload["metrics"]
      assert metric["version_number"] == version.version
      assert metric["total_runs"] == 1
      assert metric["avg_pass_rate"] == 83.33
      assert metric["avg_score"] == 80.5
      assert metric["avg_cost_usd"] == 0.0015
      assert metric["avg_latency_ms"] == 300

      [provider_breakdown] = metric["provider_breakdown"]
      assert provider_breakdown["provider_name"] == "Evolution Provider"
      assert provider_breakdown["runs"] == 1
    end

    test "downloads evolution metrics as CSV", %{conn: conn} do
      prompt = prompt_fixture_with_version(%{name: "CSV Export Prompt"})
      prompt = Aludel.Prompts.get_prompt_with_versions!(prompt.id)
      version = hd(prompt.versions)
      suite = suite_fixture(%{name: "CSV Suite", prompt_id: prompt.id})
      provider = provider_fixture(%{name: "CSV Provider"})

      _suite_run =
        suite_run_fixture(%{
          suite_id: suite.id,
          prompt_version_id: version.id,
          provider_id: provider.id,
          passed: 10,
          failed: 2,
          avg_cost_usd: Decimal.new("0.0020"),
          avg_latency_ms: 400,
          avg_score: Decimal.new("90.0")
        })

      conn = get(conn, "/prompts/#{prompt.id}/evolution/export/csv")

      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "text/csv"
      assert get_resp_header(conn, "cache-control") == ["no-store, max-age=0"]
      assert get_resp_header(conn, "pragma") == ["no-cache"]
      assert get_resp_header(conn, "expires") == ["0"]

      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ ~r/attachment; filename="prompt-evolution-.*\.csv"/

      csv_content = conn.resp_body
      [header | rows] = String.split(csv_content, "\n", trim: true)

      assert header ==
               "version,created_at,total_runs,avg_pass_rate,avg_score,avg_cost_usd,avg_latency_ms,provider_name,provider_runs,provider_pass_rate,provider_score,provider_cost_usd,provider_latency_ms"

      assert length(rows) == 1
      row = hd(rows)
      assert row =~ "#{version.version}"
      assert row =~ "83.33"
      assert row =~ "90.0"
      assert row =~ "0.0020"
      assert row =~ "400"
      assert row =~ "CSV Provider"
    end

    test "returns 404 when prompt not found", %{conn: conn} do
      assert_error_sent 404, fn ->
        get(conn, "/prompts/00000000-0000-0000-0000-000000000000/evolution/export/json")
      end
    end

    test "returns error for unsupported format", %{conn: conn} do
      prompt = prompt_fixture_with_version(%{name: "Format Test Prompt"})

      conn = get(conn, "/prompts/#{prompt.id}/evolution/export/xml")

      assert conn.status == 400
      assert conn.resp_body =~ "Unsupported format"
    end
  end
end
