defmodule Aludel.Runs.Executor do
  @moduledoc """
  Owns run launch and provider execution under explicit supervision.
  """

  import Ecto.Query, only: [from: 2]

  require Logger

  alias Aludel.Execution, as: AppExecution
  alias Aludel.Execution.Artifact
  alias Aludel.Providers.Provider
  alias Aludel.PubSub
  alias Aludel.Runs.{Execution, Run, RunResult}
  alias Ecto.Changeset
  alias Ecto.Multi

  @execution_supervisor Aludel.Runs.ExecutorSupervisor
  @default_max_concurrency 3
  @default_timeout_ms 120_000

  @type execution_result :: {:ok, Execution.t()} | {:error, :empty_providers | term()}

  @doc """
  Launches a run under the executor supervisor.
  """
  @spec launch(Run.t(), [Provider.t()]) ::
          {:ok, pid()} | {:ok, pid(), term()} | {:error, :empty_providers | term()}
  def launch(%Run{}, []), do: {:error, :empty_providers}

  def launch(%Run{} = run, providers) when is_list(providers) do
    Task.Supervisor.start_child(@execution_supervisor, fn ->
      case execute(run, providers) do
        {:ok, %Execution{status: :ok}} ->
          :ok

        {:ok, %Execution{status: status, failures: failures}} ->
          Logger.warning(
            "Run execution completed with provider failures for run #{run.id} " <>
              "(status=#{status}, failures=#{inspect(failures)})"
          )

          :ok

        {:error, reason} ->
          Logger.error("Run execution failed for run #{run.id}: #{inspect(reason)}")

          exit({:run_execution_failed, reason})
      end
    end)
  end

  @doc """
  Executes a run against one or more providers and returns a structured outcome.
  """
  @spec execute(Run.t(), [Provider.t()]) :: execution_result()
  def execute(%Run{}, []), do: {:error, :empty_providers}

  def execute(%Run{} = run, providers) when is_list(providers) do
    run = preload_prompt_version(run)

    case mark_run_running(run) do
      {:ok, running_run} ->
        with :ok <-
               validate_variable_values(
                 running_run.prompt_version.variables,
                 running_run.variable_values
               ),
             {:ok, pending_results} <- create_pending_results(running_run, providers),
             provider_outcomes <-
               execute_providers(
                 running_run,
                 Enum.zip(providers, pending_results)
               ),
             failures = collect_failures(provider_outcomes),
             {:ok, updated_run} <- complete_run(running_run, length(providers), failures) do
          {:ok,
           %Execution{
             failures: failures,
             provider_results: updated_run.run_results,
             run: updated_run,
             status: execution_status(length(providers), length(failures))
           }}
        else
          {:error, reason} ->
            fail_run(running_run, reason)
        end

      {:error, reason} ->
        fail_run(run, reason)
    end
  end

  defp preload_prompt_version(%Run{prompt_version: %Ecto.Association.NotLoaded{}} = run) do
    repo().preload(run, :prompt_version)
  end

  defp preload_prompt_version(%Run{} = run), do: run

  defp execute_providers(run, provider_results) do
    case execution_mode() do
      :sequential ->
        Enum.map(provider_results, fn {provider, run_result} ->
          {provider, execute_provider(run, run_result, provider)}
        end)

      _mode ->
        stream_provider_executions(run, provider_results)
    end
  end

  defp stream_provider_executions(run, provider_results) do
    provider_results
    |> Enum.zip(
      Task.Supervisor.async_stream_nolink(
        @execution_supervisor,
        provider_results,
        fn {provider, run_result} ->
          execute_provider(run, run_result, provider)
        end,
        max_concurrency: execution_max_concurrency(),
        timeout: execution_timeout_ms()
      )
    )
    |> Enum.map(fn
      {{provider, _run_result}, {:ok, outcome}} ->
        {provider, outcome}

      {{provider, run_result}, {:exit, reason}} ->
        failure_reason = {:task_exit, reason}

        artifacts =
          run
          |> execution_request(provider)
          |> Artifact.start_unavailable(failure_reason)

        {provider, create_error_result(run.id, run_result, provider, failure_reason, artifacts)}
    end)
  end

  defp execute_provider(run, run_result, provider) do
    request = execution_request(run, provider)

    with {:ok, run_result} <- mark_run_result_running(run_result),
         result <- AppExecution.execute_with_artifacts(request) do
      case result do
        {:ok, llm_result} ->
          complete_run_result(run.id, run_result, provider, llm_result)

        {:error, reason, artifacts} ->
          create_error_result(run.id, run_result, provider, reason, artifacts)
      end
    else
      {:error, changeset} ->
        log_run_result_failure(run.id, provider.id, changeset)
        {:error, provider_failure(provider, {:result_transition_failed, changeset.errors})}
    end
  end

  defp execution_request(run, provider) do
    %{
      kind: :run,
      prompt_version: run.prompt_version,
      variables: run.variable_values,
      provider: provider,
      documents: [],
      metadata: %{
        run_id: run.id,
        prompt_id: run.prompt_version.prompt_id,
        prompt_version_id: run.prompt_version.id
      }
    }
  end

  defp complete_run_result(run_id, run_result, provider, result) do
    case update_run_result(run_result, %{
           output: result.output,
           input_tokens: result.input_tokens,
           output_tokens: result.output_tokens,
           latency_ms: result.latency_ms,
           cost_usd: result.cost_usd,
           metadata: result.metadata,
           artifacts: result.artifacts,
           status: :completed,
           completed_at: now(),
           error: nil
         }) do
      {:ok, run_result} ->
        broadcast_update(run_id, run_result.id, :completed, result.output)
        {:ok, run_result}

      {:error, changeset} ->
        log_run_result_failure(run_id, provider.id, changeset)
        {:error, provider_failure(provider, {:result_persistence_failed, changeset.errors})}
    end
  end

  defp create_error_result(run_id, run_result, provider, reason, artifacts) do
    inspected_reason = inspect(reason)

    case persist_error_result(run_result, %{
           status: :error,
           error: inspected_reason,
           artifacts: artifacts,
           completed_at: now()
         }) do
      {:ok, run_result} ->
        broadcast_update(run_id, run_result.id, :error, inspected_reason)
        {:error, provider_failure(provider, reason)}

      {:error, changeset} ->
        log_run_result_failure(run_id, provider.id, changeset)
        {:error, provider_failure(provider, {:result_persistence_failed, changeset.errors})}
    end
  end

  defp collect_failures(provider_outcomes) do
    Enum.reduce(provider_outcomes, [], fn
      {_provider, {:ok, _run_result}}, failures ->
        failures

      {_provider, {:error, failure}}, failures ->
        [failure | failures]
    end)
    |> Enum.reverse()
  end

  defp execution_status(_provider_count, 0), do: :ok

  defp execution_status(provider_count, failure_count) when provider_count == failure_count do
    :error
  end

  defp execution_status(_provider_count, _failure_count), do: :partial_failure

  defp run_status(_provider_count, 0), do: :completed

  defp run_status(provider_count, failure_count) when provider_count == failure_count do
    :failed
  end

  defp run_status(_provider_count, _failure_count), do: :partial_failure

  defp provider_failure(provider, reason) do
    %{
      provider_id: provider.id,
      provider_name: provider.name,
      reason: reason
    }
  end

  defp reload_run(run_id) do
    case repo().get(Run, run_id) do
      nil ->
        {:error, :run_not_found}

      run ->
        {:ok, repo().preload(run, prompt_version: :prompt, run_results: :provider)}
    end
  end

  defp validate_variable_values(expected_variables, variable_values) do
    missing_variables =
      Enum.reject(expected_variables, fn variable ->
        Map.has_key?(variable_values, variable)
      end)

    case missing_variables do
      [] ->
        :ok

      _missing_variables ->
        {:error, {:missing_variables, missing_variables}}
    end
  end

  defp create_run_result(attrs) do
    %RunResult{}
    |> RunResult.changeset(attrs)
    |> repo().insert()
  end

  defp update_run_result(%RunResult{} = run_result, attrs) do
    run_result
    |> RunResult.changeset(attrs)
    |> repo().update()
  end

  defp mark_run_running(%Run{} = run) do
    transition_timestamp = now()

    from(r in Run, where: r.id == ^run.id and r.status == :pending)
    |> repo().update_all(
      set: [
        status: :running,
        started_at: transition_timestamp,
        completed_at: nil,
        error_summary: nil
      ]
    )
    |> case do
      {1, _} ->
        with {:ok, updated_run} <- reload_run(run.id) do
          broadcast_run_update(updated_run.id, updated_run.status)
          {:ok, updated_run}
        end

      {0, _} ->
        {:error, :run_not_found}
    end
  end

  defp create_pending_results(%Run{} = run, providers) do
    multi =
      providers
      |> Enum.with_index()
      |> Enum.reduce(Multi.new(), fn {provider, index}, multi ->
        Multi.insert(
          multi,
          {:run_result, index},
          RunResult.changeset(%RunResult{}, %{
            run_id: run.id,
            provider_id: provider.id,
            status: :pending
          })
        )
      end)

    case repo().transaction(multi) do
      {:ok, results} ->
        pending_results =
          providers
          |> Enum.with_index()
          |> Enum.map(fn {_provider, index} ->
            run_result = Map.fetch!(results, {:run_result, index})
            broadcast_update(run.id, run_result.id, :pending, nil)
            run_result
          end)

        {:ok, pending_results}

      {:error, _operation, changeset, _changes_so_far} ->
        {:error, {:pending_result_persistence_failed, changeset.errors}}
    end
  end

  defp mark_run_result_running(%RunResult{} = run_result) do
    update_run_result(run_result, %{
      status: :running,
      started_at: now(),
      completed_at: nil
    })
    |> case do
      {:ok, updated_result} = result ->
        broadcast_update(
          updated_result.run_id,
          updated_result.id,
          :running,
          updated_result.output
        )

        result

      error ->
        error
    end
  end

  defp persist_error_result(%RunResult{id: nil} = run_result, attrs) do
    attrs =
      attrs
      |> Map.put(:run_id, run_result.run_id)
      |> Map.put(:provider_id, run_result.provider_id)
      |> Map.put_new(:started_at, now())

    create_run_result(attrs)
  end

  defp persist_error_result(%RunResult{} = run_result, attrs) do
    attrs =
      attrs
      |> Map.put_new(:started_at, run_result.started_at || now())

    update_run_result(run_result, attrs)
  end

  defp complete_run(%Run{} = run, provider_count, failures) do
    final_status = run_status(provider_count, length(failures))

    run
    |> Run.execution_changeset(%{
      status: final_status,
      completed_at: now(),
      error_summary: error_summary(failures)
    })
    |> repo().update()
    |> case do
      {:ok, updated_run} ->
        broadcast_run_update(updated_run.id, updated_run.status)
        reload_run(updated_run.id)

      error ->
        error
    end
  end

  defp fail_run(%Run{} = run, reason) do
    case {run.id, reason} do
      {_run_id, :run_not_found} ->
        {:error, :run_not_found}

      {nil, _reason} ->
        {:error, reason}

      {_run_id, _reason} ->
        transition_timestamp = now()

        _ =
          run
          |> Run.execution_changeset(%{
            status: :failed,
            started_at: run.started_at || transition_timestamp,
            completed_at: transition_timestamp,
            error_summary: inspect(reason)
          })
          |> repo().update()
          |> case do
            {:ok, updated_run} ->
              broadcast_run_update(updated_run.id, updated_run.status)
              :ok

            {:error, changeset} ->
              Logger.warning("Failed to persist :failed status for run #{run.id}",
                reason: inspect(changeset.errors)
              )

              :error
          end

        {:error, reason}
    end
  end

  defp error_summary([]), do: nil

  defp error_summary(failures) do
    Enum.map_join(failures, "\n", fn failure ->
      "#{failure.provider_name}: #{inspect(failure.reason)}"
    end)
  end

  defp log_run_result_failure(run_id, provider_id, %Changeset{} = changeset) do
    Logger.warning("Failed to create run result for run #{run_id}",
      provider_id: provider_id,
      reason: inspect(changeset.errors)
    )
  end

  defp broadcast_update(run_id, result_id, status, output) do
    Phoenix.PubSub.broadcast(
      PubSub,
      "run:#{run_id}",
      {:run_result_update, result_id, status, output}
    )
  end

  defp broadcast_run_update(run_id, status) do
    Phoenix.PubSub.broadcast(
      PubSub,
      "run:#{run_id}",
      {:run_update, status}
    )
  end

  defp execution_mode do
    Application.get_env(:aludel, :run_execution_mode, :concurrent)
  end

  defp execution_max_concurrency do
    Keyword.get(llm_config(), :max_concurrency, @default_max_concurrency)
  end

  defp execution_timeout_ms do
    Keyword.get(llm_config(), :request_timeout_ms, @default_timeout_ms)
  end

  defp llm_config do
    Application.get_env(:aludel, :llm, [])
  end

  defp now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end

  defp repo, do: Aludel.Repo.get()
end
