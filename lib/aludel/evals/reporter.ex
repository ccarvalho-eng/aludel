defmodule Aludel.Evals.Reporter do
  @moduledoc """
  Renders evaluation reports for people and CI systems.

  The built-in reporter names are `:console`, `:json`, `:junit`, and
  `:github`. A custom module can also be passed directly when it implements
  this module's callback.

      {:ok, output} = Aludel.Evals.Reporter.render(suite_run, :junit)

  Reporter options are passed to the selected implementation. The JSON
  reporter, for example, accepts `pretty: true`.
  """

  alias Aludel.Evals.Report
  alias Aludel.Evals.Reporters.{Console, GitHub, JSON, JUnit}
  alias Aludel.Evals.SuiteRun

  @typedoc "A built-in reporter name or a custom reporter module."
  @type reporter :: :console | :json | :junit | :github | module()

  @typedoc "A stable error returned before or while rendering a report."
  @type error :: :unknown_reporter | :invalid_reporter_output

  @callback render(Report.t(), keyword()) :: {:ok, iodata()} | {:error, term()}

  @reporters %{
    console: Console,
    github: GitHub,
    json: JSON,
    junit: JUnit
  }

  @doc "Renders a suite run with a built-in or custom reporter."
  @spec render(SuiteRun.t() | Report.t(), reporter(), keyword()) ::
          {:ok, String.t()} | {:error, error() | term()}
  def render(suite_run_or_report, reporter, options \\ [])

  def render(%SuiteRun{} = suite_run, reporter, options) do
    suite_run
    |> Report.from_suite_run()
    |> render(reporter, options)
  end

  def render(%Report{} = report, reporter, options) do
    with {:ok, reporter_module} <- resolve_reporter(reporter) do
      render_with(reporter_module, report, options)
    end
  end

  @doc "Renders a report and raises `ArgumentError` when rendering fails."
  @spec render!(SuiteRun.t() | Report.t(), reporter(), keyword()) :: String.t()
  def render!(suite_run_or_report, reporter, options \\ []) do
    case render(suite_run_or_report, reporter, options) do
      {:ok, output} ->
        output

      {:error, reason} ->
        raise ArgumentError, "could not render evaluation report: #{inspect(reason)}"
    end
  end

  defp resolve_reporter(reporter) when is_atom(reporter) do
    case Map.fetch(@reporters, reporter) do
      {:ok, reporter_module} -> {:ok, reporter_module}
      :error -> resolve_custom_reporter(reporter)
    end
  end

  defp resolve_reporter(_reporter) do
    {:error, :unknown_reporter}
  end

  defp resolve_custom_reporter(reporter) do
    if Code.ensure_loaded?(reporter) and function_exported?(reporter, :render, 2) do
      {:ok, reporter}
    else
      {:error, :unknown_reporter}
    end
  end

  defp render_with(reporter_module, report, options) do
    case reporter_module.render(report, options) do
      {:ok, rendered} -> to_binary(rendered)
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :invalid_reporter_output}
    end
  end

  defp to_binary(rendered) do
    {:ok, IO.iodata_to_binary(rendered)}
  rescue
    ArgumentError -> {:error, :invalid_reporter_output}
  end
end
