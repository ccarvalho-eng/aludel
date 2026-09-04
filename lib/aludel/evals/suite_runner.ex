defmodule Aludel.Evals.SuiteRunner do
  @moduledoc """
  Owns suite execution launch under explicit supervision.
  """

  alias Aludel.Evals
  alias Aludel.Evals.SuiteRun
  alias Aludel.Prompts
  alias Aludel.Providers
  alias Aludel.TaskSupervisor
  alias Ecto.NoResultsError

  @type execution_result :: {:ok, SuiteRun.t()} | {:error, term()}

  @spec launch(pid(), binary(), binary(), binary(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def launch(recipient, suite_id, version_id, provider_id, opts \\ [])
      when is_pid(recipient) and is_binary(suite_id) and is_binary(version_id) and
             is_binary(provider_id) and is_list(opts) do
    Task.Supervisor.start_child(TaskSupervisor, fn ->
      send(recipient, {:suite_completed, execute(suite_id, version_id, provider_id, opts)})
    end)
  end

  @spec execute(binary(), binary(), binary(), keyword()) :: execution_result()
  def execute(suite_id, version_id, provider_id, opts \\ [])
      when is_binary(suite_id) and is_binary(version_id) and is_binary(provider_id) do
    with {:ok, suite} <- fetch_suite(suite_id),
         {:ok, version} <- fetch_prompt_version(version_id),
         {:ok, provider} <- fetch_provider(provider_id) do
      run_execution(suite, version, provider, opts)
    end
  end

  defp run_execution(suite, version, provider, opts) do
    Evals.execute_suite(suite, version, provider, opts)
  rescue
    error ->
      {:error, {:execution_failed, Exception.message(error)}}
  catch
    kind, reason ->
      {:error, {:execution_failed, {kind, reason}}}
  end

  defp fetch_suite(suite_id) do
    {:ok, Evals.get_suite_with_test_cases!(suite_id)}
  rescue
    error in [NoResultsError] -> {:error, map_lookup_error(error, :suite_not_found)}
  end

  defp fetch_prompt_version(version_id) do
    {:ok, Prompts.get_prompt_version!(version_id)}
  rescue
    error in [NoResultsError] -> {:error, map_lookup_error(error, :prompt_version_not_found)}
  end

  defp fetch_provider(provider_id) do
    {:ok, Providers.get_provider!(provider_id)}
  rescue
    error in [NoResultsError] -> {:error, map_lookup_error(error, :provider_not_found)}
  end

  defp map_lookup_error(_error, reason), do: reason
end
