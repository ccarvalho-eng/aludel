defmodule Mix.Tasks.Aludel.Eval do
  @moduledoc """
  Runs one Aludel evaluation suite and emits a report.

      mix aludel.eval \
        --suite-id SUITE_ID \
        --prompt-version-id PROMPT_VERSION_ID \
        --provider-id PROVIDER_ID \
        --format json

  Supported formats are `json` (the default), `console`, `junit`, and
  `github`. Use `--output PATH` to write the report to a file instead of
  standard output. JSON output uses the versioned Aludel report schema. JUnit
  omits generated responses unless `--include-output` is set.

  The task exits unsuccessfully when arguments or targets are invalid, execution
  cannot complete, or the active suite quality policy does not pass. Suites
  without a quality policy retain the all-test-cases-must-pass behavior.
  """

  @shortdoc "Runs an Aludel suite and emits a CI report"
  @requirements ["app.start"]

  use Mix.Task

  alias Aludel.Evals
  alias Aludel.Evals.{Report, Reporter}
  alias Aludel.Prompts
  alias Aludel.Providers

  @schema_version 2
  @switches [
    suite_id: :string,
    prompt_version_id: :string,
    provider_id: :string,
    format: :string,
    output: :string,
    pretty: :boolean,
    include_output: :boolean
  ]
  @required_options [:suite_id, :prompt_version_id, :provider_id]
  @reporters %{
    "console" => :console,
    "github" => :github,
    "json" => :json,
    "junit" => :junit
  }

  @impl Mix.Task
  def run(args) do
    case args |> parse_options() |> execute() do
      {:ok, %Report{status: "passed"} = report, options} ->
        emit_report(report, options)

      {:ok, %Report{} = report, options} ->
        emit_report(report, options)
        Mix.raise("Evaluation did not pass")

      {:error, error} ->
        emit(error_payload(error))
        Mix.raise(error.message)
    end
  end

  defp parse_options(args) do
    case OptionParser.parse(args, strict: @switches) do
      {options, [], []} -> validate_required_options(options)
      {_options, _positional, _invalid} -> {:error, cli_error("invalid_arguments", usage())}
    end
  end

  defp validate_required_options(options) do
    missing_options = Enum.reject(@required_options, &Keyword.has_key?(options, &1))

    if missing_options == [] do
      options
      |> Map.new()
      |> validate_reporter()
    else
      missing_flags = Enum.map_join(missing_options, ", ", &option_flag/1)
      {:error, cli_error("invalid_arguments", "Missing required options: #{missing_flags}")}
    end
  end

  defp execute({:error, error}) do
    {:error, error}
  end

  defp execute({:ok, options}) do
    with {:ok, suite} <- fetch_target("suite", fn -> Evals.get_suite!(options.suite_id) end),
         {:ok, prompt_version} <-
           fetch_target("prompt_version", fn ->
             Prompts.get_prompt_version!(options.prompt_version_id)
           end),
         {:ok, provider} <-
           fetch_target("provider", fn -> Providers.get_provider!(options.provider_id) end),
         :ok <- validate_prompt_version(suite, prompt_version),
         {:ok, suite_run} <- execute_suite(suite, prompt_version, provider) do
      {:ok, Report.from_suite_run(suite_run), options}
    end
  end

  defp validate_reporter(options) do
    format = Map.get(options, :format, "json")

    with {:ok, reporter} <- fetch_reporter(format),
         :ok <- validate_reporter_options(format, options) do
      {:ok, Map.put(options, :reporter, reporter)}
    end
  end

  defp fetch_reporter(format) do
    case Map.fetch(@reporters, format) do
      {:ok, reporter} ->
        {:ok, reporter}

      :error ->
        {:error,
         cli_error(
           "invalid_format",
           "format must be one of: console, github, json, junit"
         )}
    end
  end

  defp validate_reporter_options(format, options) do
    cond do
      Map.get(options, :pretty, false) and format != "json" ->
        {:error, cli_error("invalid_options", "--pretty requires --format json")}

      Map.get(options, :include_output, false) and format != "junit" ->
        {:error, cli_error("invalid_options", "--include-output requires --format junit")}

      true ->
        :ok
    end
  end

  defp fetch_target(resource, fetch) do
    {:ok, fetch.()}
  rescue
    _error in [Ecto.NoResultsError, Ecto.Query.CastError] ->
      {:error, cli_error("#{resource}_not_found", "#{resource} was not found")}
  end

  defp validate_prompt_version(suite, prompt_version) do
    if prompt_version.prompt_id == suite.prompt_id do
      :ok
    else
      {:error,
       cli_error(
         "prompt_version_mismatch",
         "prompt_version does not belong to the suite prompt"
       )}
    end
  end

  defp execute_suite(suite, prompt_version, provider) do
    case Evals.execute_suite(suite, prompt_version, provider) do
      {:ok, suite_run} ->
        {:ok, suite_run}

      {:error, _reason} ->
        {:error, cli_error("execution_failed", "Suite execution could not be persisted")}
    end
  rescue
    _error ->
      {:error, cli_error("execution_failed", "Suite execution failed")}
  catch
    _kind, _reason ->
      {:error, cli_error("execution_failed", "Suite execution failed")}
  end

  defp error_payload(error) do
    %{
      type: "aludel_eval",
      schema_version: @schema_version,
      status: "error",
      error: error
    }
  end

  defp cli_error(code, message) do
    %{code: code, message: message}
  end

  defp emit(payload) do
    payload
    |> Jason.encode!()
    |> Mix.shell().info()
  end

  defp emit_report(report, options) do
    reporter_options = [
      pretty: Map.get(options, :pretty, false),
      include_output: Map.get(options, :include_output, false)
    ]

    case Reporter.render(report, options.reporter, reporter_options) do
      {:ok, output} -> write_report(output, Map.get(options, :output))
      {:error, _reason} -> Mix.raise("Evaluation report could not be rendered")
    end
  end

  defp write_report(output, nil) do
    Mix.shell().info(output)
  end

  defp write_report(output, path) do
    case File.write(path, output <> trailing_newline(output)) do
      :ok ->
        :ok

      {:error, reason} ->
        Mix.raise("Evaluation report could not be written: #{:file.format_error(reason)}")
    end
  end

  defp trailing_newline(output) do
    if String.ends_with?(output, "\n"), do: "", else: "\n"
  end

  defp option_flag(option) do
    "--#{option |> Atom.to_string() |> String.replace("_", "-")}"
  end

  defp usage do
    "Usage: mix aludel.eval --suite-id ID --prompt-version-id ID --provider-id ID " <>
      "[--format console|github|json|junit] [--output PATH] [--pretty] [--include-output]"
  end
end
