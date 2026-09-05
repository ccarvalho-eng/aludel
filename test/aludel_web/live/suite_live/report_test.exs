defmodule Aludel.Web.SuiteLive.ReportTest do
  use Aludel.Web.ConnCase, async: false

  import Aludel.EvalsFixtures
  import Aludel.PromptsFixtures
  import Aludel.ProvidersFixtures
  import Phoenix.LiveViewTest

  test "previews and downloads every built-in report format", %{conn: conn} do
    %{suite_run: suite_run, output: output} = report_fixture()

    {:ok, view, _html} = live(conn, "/suites/runs/#{suite_run.id}/report")

    assert has_element?(view, "#evaluation-report-form")
    assert has_element?(view, "#report-preview", "Aludel evaluation PASSED")

    assert has_element?(
             view,
             "#download-evaluation-report[href='/suites/runs/#{suite_run.id}/report/console']",
             "Download console report"
           )

    view
    |> form("#evaluation-report-form", report: %{format: "json"})
    |> render_change()

    assert has_element?(view, "#report-preview", ~s("schema_version": 2))
    assert has_element?(view, "#report-preview", output)

    view
    |> form("#evaluation-report-form", report: %{format: "junit"})
    |> render_change()

    assert has_element?(view, "#junit-output-option")
    assert has_element?(view, "#report-preview", "<testsuites")
    refute has_element?(view, "#report-preview", output)

    view
    |> form("#evaluation-report-form", report: %{format: "junit", include_output: "true"})
    |> render_change()

    assert has_element?(view, "#report-preview", output)

    assert has_element?(
             view,
             "#download-evaluation-report[href='/suites/runs/#{suite_run.id}/report/junit?include_output=true']",
             "Download JUnit XML"
           )

    view
    |> form("#evaluation-report-form", report: %{format: "github"})
    |> render_change()

    assert has_element?(view, "#report-preview", "::notice title=Aludel evaluation")
  end

  test "falls back to the safe console preview for an unsupported format", %{conn: conn} do
    %{suite_run: suite_run} = report_fixture()
    {:ok, view, _html} = live(conn, "/suites/runs/#{suite_run.id}/report")

    render_hook(view, "preview", %{
      "report" => %{"format" => "Elixir.System", "include_output" => "true"}
    })

    assert has_element?(view, "#report-preview", "Aludel evaluation PASSED")
    refute has_element?(view, "#junit-output-option")
  end

  defp report_fixture do
    prompt = prompt_fixture_with_version()
    suite = suite_fixture(%{prompt_id: prompt.id})
    version = List.first(prompt.versions)
    provider = provider_fixture()
    test_case = test_case_fixture(%{suite_id: suite.id})
    output = "A model response that may contain sensitive data"

    suite_run =
      suite_run_fixture(%{
        suite_id: suite.id,
        prompt_version_id: version.id,
        provider_id: provider.id,
        passed: 1,
        failed: 0,
        results: [
          %{
            "test_case_id" => test_case.id,
            "passed" => true,
            "output" => output,
            "assertion_results" => [],
            "latency_ms" => 120
          }
        ]
      })

    %{suite_run: suite_run, output: output}
  end
end
