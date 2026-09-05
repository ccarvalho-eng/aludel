defmodule Aludel.Web.ExportController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json]

  import Plug.Conn

  alias Aludel.Evals
  alias Aludel.Evals.Reporter
  alias Aludel.Evals.SuitePolicy
  alias Aludel.Prompts
  alias Aludel.Prompts.Evolution.Export, as: EvolutionExport
  alias Aludel.Runs
  alias Decimal

  def run_result(conn, %{"id" => id}) do
    payload =
      id
      |> Runs.get_run_result_for_export!()
      |> serialize_run_result_export()

    send_json_download(conn, payload, "run-result-#{id}.json")
  end

  def suite_run(conn, %{"id" => id}) do
    payload =
      id
      |> Evals.get_suite_run_for_export!()
      |> serialize_suite_run_export()

    send_json_download(conn, payload, "suite-run-#{id}.json")
  end

  @doc false
  @spec suite_report(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def suite_report(conn, %{"id" => id, "format" => format} = path_params) do
    conn = fetch_query_params(conn)
    params = Map.merge(path_params, conn.query_params)

    with {:ok, reporter, extension, content_type} <- report_config(format),
         suite_run <- Evals.get_suite_run_for_export!(id),
         {:ok, rendered} <- Reporter.render(suite_run, reporter, report_options(format, params)) do
      send_report_download(conn, rendered, id, extension, content_type)
    else
      :error ->
        conn
        |> put_status(400)
        |> send_resp(400, "Unsupported report format")

      {:error, _reason} ->
        conn
        |> put_status(500)
        |> send_resp(500, "Report could not be rendered")
    end
  end

  @doc """
  Exports prompt evolution metrics in JSON or CSV format.

  Returns a timestamped download with evolution metrics including version history,
  performance data, and provider-specific breakdowns.
  """
  @spec evolution(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def evolution(conn, %{"id" => id, "format" => format}) do
    prompt = Prompts.get_prompt!(id)
    metrics = Prompts.get_evolution_metrics(id)

    case format do
      "json" ->
        payload = EvolutionExport.to_json(prompt, metrics)
        timestamp = DateTime.utc_now() |> DateTime.to_unix()
        filename = "prompt-evolution-#{timestamp}.json"
        send_json_download(conn, payload, filename)

      "csv" ->
        csv_content = EvolutionExport.to_csv(metrics)
        timestamp = DateTime.utc_now() |> DateTime.to_unix()
        filename = "prompt-evolution-#{timestamp}.csv"

        conn
        |> put_resp_header("cache-control", "no-store, max-age=0")
        |> put_resp_header("pragma", "no-cache")
        |> put_resp_header("expires", "0")
        |> send_download({:binary, csv_content},
          filename: filename,
          content_type: "text/csv"
        )

      _ ->
        conn
        |> put_status(400)
        |> send_resp(400, "Unsupported format. Use 'json' or 'csv'.")
    end
  end

  defp send_json_download(conn, payload, filename) do
    encoded_payload = Jason.encode!(payload, pretty: true)

    conn
    |> put_resp_header("cache-control", "no-store, max-age=0")
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("expires", "0")
    |> send_download({:binary, encoded_payload},
      filename: filename,
      content_type: "application/json"
    )
  end

  defp send_report_download(conn, rendered, id, extension, content_type) do
    conn
    |> put_resp_header("cache-control", "no-store, max-age=0")
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("expires", "0")
    |> send_download({:binary, rendered},
      filename: "evaluation-report-#{id}#{extension}",
      content_type: content_type
    )
  end

  defp report_config("console") do
    {:ok, :console, ".txt", "text/plain; charset=utf-8"}
  end

  defp report_config("json") do
    {:ok, :json, ".json", "application/json"}
  end

  defp report_config("junit") do
    {:ok, :junit, ".xml", "application/xml"}
  end

  defp report_config("github") do
    {:ok, :github, ".txt", "text/plain; charset=utf-8"}
  end

  defp report_config(_format) do
    :error
  end

  defp report_options("json", _params) do
    [pretty: true]
  end

  defp report_options("junit", params) do
    [include_output: Map.get(params, "include_output") == "true"]
  end

  defp report_options(_format, _params) do
    []
  end

  defp serialize_run_result_export(result) do
    %{
      type: "run_result",
      exported_at: iso8601(DateTime.utc_now()),
      run: %{
        id: result.run.id,
        name: result.run.name,
        status: to_string(result.run.status),
        prompt_version_id: result.run.prompt_version_id,
        prompt_id: result.run.prompt_version.prompt.id,
        prompt_name: result.run.prompt_version.prompt.name,
        variable_values: result.run.variable_values,
        started_at: iso8601(result.run.started_at),
        completed_at: iso8601(result.run.completed_at)
      },
      result: %{
        id: result.id,
        provider: serialize_provider(result.provider),
        status: to_string(result.status),
        output: result.output,
        error: result.error,
        input_tokens: result.input_tokens,
        output_tokens: result.output_tokens,
        latency_ms: result.latency_ms,
        cost_usd: result.cost_usd,
        metadata: result.metadata,
        artifacts: result.artifacts,
        started_at: iso8601(result.started_at),
        completed_at: iso8601(result.completed_at),
        inserted_at: iso8601(result.inserted_at),
        updated_at: iso8601(result.updated_at)
      }
    }
  end

  defp serialize_suite_run_export(suite_run) do
    %{
      type: "suite_run",
      exported_at: iso8601(DateTime.utc_now()),
      suite_run: %{
        id: suite_run.id,
        suite: %{
          id: suite_run.suite.id,
          name: suite_run.suite.name
        },
        prompt_version: %{
          id: suite_run.prompt_version.id,
          version: suite_run.prompt_version.version,
          prompt_id: suite_run.prompt_version.prompt_id
        },
        provider: serialize_provider(suite_run.provider),
        quality_policy: serialize_quality_policy(suite_run),
        summary: %{
          passed: suite_run.passed,
          failed: suite_run.failed,
          total: suite_run.passed + suite_run.failed,
          avg_score: decimal_to_float(suite_run.avg_score),
          avg_cost_usd: decimal_to_float(suite_run.avg_cost_usd),
          avg_latency_ms: suite_run.avg_latency_ms
        },
        results: Enum.map(suite_run.results, &serialize_suite_result/1),
        inserted_at: iso8601(suite_run.inserted_at),
        updated_at: iso8601(suite_run.updated_at)
      }
    }
  end

  defp serialize_quality_policy(%{suite_policy: %SuitePolicy{} = suite_policy} = suite_run) do
    %{
      id: suite_policy.id,
      version: suite_policy.version,
      definition: suite_policy.definition,
      result: suite_run.quality_policy_result
    }
  end

  defp serialize_quality_policy(_suite_run) do
    nil
  end

  defp serialize_suite_result(result) do
    %{
      test_case_id: result["test_case_id"],
      test_case_metadata: result["test_case_metadata"],
      status: if(result["passed"], do: "passed", else: "failed"),
      passed: result["passed"],
      score: result["score"],
      output: result["output"],
      error: suite_result_error(result),
      input_tokens: result["input_tokens"],
      output_tokens: result["output_tokens"],
      latency_ms: result["latency_ms"],
      cost_usd: result["cost_usd"],
      metadata: result["metadata"],
      artifacts: result["artifacts"],
      assertion_results: Map.get(result, "assertion_results", []),
      retry_count: result["retry_count"],
      retried_at: result["retried_at"]
    }
  end

  defp serialize_provider(provider) do
    %{
      id: provider.id,
      name: provider.name,
      type: to_string(provider.provider),
      model: provider.model
    }
  end

  defp suite_result_error(%{"passed" => false} = result) do
    assertion_results = Map.get(result, "assertion_results", [])

    if assertion_results == [], do: result["output"], else: nil
  end

  defp suite_result_error(_result), do: nil

  defp decimal_to_float(nil), do: nil
  defp decimal_to_float(%Decimal{} = decimal), do: Decimal.to_float(decimal)

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
