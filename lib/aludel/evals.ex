defmodule Aludel.Evals do
  @moduledoc """
  Context for managing evaluation suites, test cases, quality policies, and runs.
  """

  import Ecto.Query

  alias Aludel.Evals.{
    AssertionEvaluator,
    QualityPolicy,
    Sampling,
    Suite,
    SuitePolicy,
    SuiteRun,
    SuiteRunner,
    TestCase,
    TestCaseDocument
  }

  alias Aludel.Evals.Metric.Context
  alias Aludel.Execution
  alias Aludel.Execution.Artifact
  alias Aludel.Prompts.PromptVersion
  alias Aludel.Providers.Provider
  alias Aludel.Storage
  alias Ecto.Association.NotLoaded
  alias Ecto.Changeset
  alias Ecto.Multi

  # Suite functions

  @doc """
  Lists all suites in the system.
  """
  @spec list_suites() :: [Suite.t()]
  def list_suites do
    repo().all(Suite)
  end

  @doc """
  Lists evaluation suites for one prompt, ordered by name.
  """
  @spec list_suites_for_prompt(binary()) :: [Suite.t()]
  def list_suites_for_prompt(prompt_id) do
    Suite
    |> where([suite], suite.prompt_id == ^prompt_id)
    |> order_by([suite], asc: suite.name)
    |> repo().all()
  end

  @doc """
  Lists all suites with their associated prompt preloaded.
  """
  @spec list_suites_with_prompt() :: [Suite.t()]
  def list_suites_with_prompt do
    Suite
    |> preload(:prompt)
    |> repo().all()
  end

  @doc """
  Gets a suite by ID, raising if not found.
  """
  @spec get_suite!(binary()) :: Suite.t()
  def get_suite!(id) do
    repo().get!(Suite, id)
  end

  @doc """
  Gets a suite by ID with prompt preloaded, raising if not found.
  """
  @spec get_suite_with_prompt!(binary()) :: Suite.t()
  def get_suite_with_prompt!(id) do
    Suite
    |> repo().get!(id)
    |> repo().preload(:prompt)
  end

  @doc """
  Gets a suite with all test cases preloaded.
  """
  @spec get_suite_with_test_cases!(binary()) :: Suite.t()
  def get_suite_with_test_cases!(id) do
    Suite
    |> repo().get!(id)
    |> repo().preload(:test_cases)
  end

  @doc """
  Gets a suite with test cases and prompt preloaded.
  """
  @spec get_suite_with_test_cases_and_prompt!(binary()) :: Suite.t()
  def get_suite_with_test_cases_and_prompt!(id) do
    test_cases_query = from tc in TestCase, order_by: [desc: tc.inserted_at]

    Suite
    |> repo().get!(id)
    |> repo().preload(
      test_cases: {test_cases_query, [:documents, source_dataset_entry: :dataset]},
      prompt: []
    )
  end

  @doc """
  Lists immutable quality policy versions for a suite, newest first.
  """
  @spec list_suite_policies(Suite.t()) :: [SuitePolicy.t()]
  def list_suite_policies(%Suite{id: suite_id}) do
    SuitePolicy
    |> where([policy], policy.suite_id == ^suite_id)
    |> order_by([policy], desc: policy.version)
    |> repo().all()
  end

  @doc """
  Returns the latest quality policy for a suite, or `nil` when none exists.
  """
  @spec latest_suite_policy(Suite.t()) :: SuitePolicy.t() | nil
  def latest_suite_policy(%Suite{id: suite_id}) do
    SuitePolicy
    |> where([policy], policy.suite_id == ^suite_id)
    |> order_by([policy], desc: policy.version)
    |> limit(1)
    |> repo().one()
  end

  @doc """
  Creates the next immutable quality policy version for a suite.

  Version assignment locks the parent suite row so concurrent writers cannot
  create the same suite-local version.
  """
  @spec create_suite_policy(Suite.t(), map()) ::
          {:ok, SuitePolicy.t()} | {:error, Changeset.t()}
  def create_suite_policy(%Suite{id: suite_id}, definition) when is_map(definition) do
    repo().transaction(fn ->
      lock_suite!(suite_id)
      version = next_suite_policy_version(suite_id)

      %SuitePolicy{}
      |> SuitePolicy.changeset(%{
        suite_id: suite_id,
        version: version,
        definition: definition
      })
      |> repo().insert()
      |> case do
        {:ok, policy} -> policy
        {:error, changeset} -> repo().rollback(changeset)
      end
    end)
    |> case do
      {:ok, policy} -> {:ok, policy}
      {:error, %Changeset{} = changeset} -> {:error, changeset}
    end
  end

  @doc """
  Returns a changeset for tracking suite changes.
  """
  @spec change_suite(Suite.t(), map()) :: Changeset.t()
  def change_suite(%Suite{} = suite, attrs \\ %{}) do
    Suite.changeset(suite, attrs)
  end

  @doc """
  Creates a new suite.
  """
  @spec create_suite(map()) :: {:ok, Suite.t()} | {:error, Changeset.t()}
  def create_suite(attrs \\ %{}) do
    %Suite{}
    |> Suite.changeset(attrs)
    |> repo().insert()
  end

  @doc """
  Updates an existing suite.
  """
  @spec update_suite(Suite.t(), map()) ::
          {:ok, Suite.t()} | {:error, Changeset.t()}
  def update_suite(%Suite{} = suite, attrs) do
    suite
    |> Suite.changeset(attrs)
    |> repo().update()
  end

  @doc """
  Deletes a suite.
  """
  @spec delete_suite(Suite.t()) ::
          {:ok, Suite.t()} | {:error, Changeset.t()}
  def delete_suite(%Suite{} = suite) do
    repo().delete(suite)
  end

  # TestCase functions

  @doc """
  Lists all test cases in the system.
  """
  @spec list_test_cases() :: [TestCase.t()]
  def list_test_cases do
    repo().all(TestCase)
  end

  @doc """
  Gets a test case by ID, raising if not found.
  """
  @spec get_test_case!(binary()) :: TestCase.t()
  def get_test_case!(id) do
    repo().get!(TestCase, id)
  end

  @doc """
  Gets a single test case document.

  Raises `Ecto.NoResultsError` if the document does not exist.
  """
  @spec get_test_case_document!(binary()) :: TestCaseDocument.t()
  def get_test_case_document!(id) do
    repo().get!(TestCaseDocument, id)
  end

  @doc """
  Returns a changeset for tracking test case changes.
  """
  @spec change_test_case(TestCase.t(), map()) :: Changeset.t()
  def change_test_case(%TestCase{} = test_case, attrs \\ %{}) do
    TestCase.changeset(test_case, attrs)
  end

  @doc """
  Creates a new test case.
  """
  @spec create_test_case(map()) ::
          {:ok, TestCase.t()} | {:error, Changeset.t()}
  def create_test_case(attrs \\ %{}) do
    %TestCase{}
    |> TestCase.changeset(attrs)
    |> repo().insert()
  end

  @doc """
  Imports test case attributes into an existing suite as one transaction.

  The suite association is set from the supplied suite rather than accepted
  from imported attributes. If any row fails validation, no test cases are
  persisted and the failing row index is returned with its changeset.
  """
  @spec import_test_cases(Suite.t(), [map()]) ::
          {:ok, [TestCase.t()]}
          | {:error, %{row: pos_integer(), changeset: Changeset.t()}}
  def import_test_cases(%Suite{} = suite, test_case_attrs) when is_list(test_case_attrs) do
    indexed_attrs = Enum.with_index(test_case_attrs, 1)

    multi =
      Enum.reduce(indexed_attrs, Multi.new(), fn {attrs, row}, multi ->
        sanitized_attrs = Map.drop(attrs, [:suite_id, "suite_id"])

        changeset =
          %TestCase{suite_id: suite.id}
          |> TestCase.changeset(sanitized_attrs)

        Multi.insert(multi, {:test_case, row}, changeset)
      end)

    case repo().transaction(multi) do
      {:ok, changes} ->
        test_cases =
          Enum.map(indexed_attrs, fn {_attrs, row} ->
            Map.fetch!(changes, {:test_case, row})
          end)

        {:ok, test_cases}

      {:error, {:test_case, row}, changeset, _changes} ->
        {:error, %{row: row, changeset: changeset}}
    end
  end

  @doc """
  Updates an existing test case.
  """
  @spec update_test_case(TestCase.t(), map()) ::
          {:ok, TestCase.t()} | {:error, Changeset.t()}
  def update_test_case(%TestCase{} = test_case, attrs) do
    test_case
    |> TestCase.changeset(attrs)
    |> repo().update()
  end

  @doc """
  Deletes a test case.
  """
  @spec delete_test_case(TestCase.t()) ::
          {:ok, TestCase.t()} | {:error, Changeset.t()}
  def delete_test_case(%TestCase{} = test_case) do
    repo().delete(test_case)
  end

  # SuiteRun functions

  @doc """
  Lists all suite runs in the system.
  """
  @spec list_suite_runs() :: [SuiteRun.t()]
  def list_suite_runs do
    repo().all(SuiteRun)
  end

  @doc """
  Gets suite runs for a specific suite.
  """
  @spec list_suite_runs_for_suite(binary()) :: [SuiteRun.t()]
  def list_suite_runs_for_suite(suite_id) do
    SuiteRun
    |> where([sr], sr.suite_id == ^suite_id)
    |> order_by([sr], desc: sr.inserted_at)
    |> repo().all()
  end

  @doc """
  Gets suite runs for a specific suite with prompt_version and provider
  preloaded.
  """
  @spec list_suite_runs_for_suite_with_associations(binary()) :: [SuiteRun.t()]
  def list_suite_runs_for_suite_with_associations(suite_id) do
    SuiteRun
    |> where([sr], sr.suite_id == ^suite_id)
    |> order_by([sr], desc: sr.inserted_at)
    |> preload([:prompt_version, :provider])
    |> repo().all()
  end

  @doc """
  Calculates pass rates grouped by prompt.

  Returns a list of maps with prompt info and pass rate statistics.
  """
  @spec pass_rates_by_prompt() :: [map()]
  def pass_rates_by_prompt do
    query =
      from sr in SuiteRun,
        join: pv in assoc(sr, :prompt_version),
        join: p in assoc(pv, :prompt),
        group_by: [p.id, p.name],
        select: %{
          prompt_id: p.id,
          prompt_name: p.name,
          total_passed: sum(sr.passed),
          total_failed: sum(sr.failed)
        }

    repo().all(query)
  end

  @doc """
  Gets a suite run by ID, raising if not found.
  """
  @spec get_suite_run!(binary()) :: SuiteRun.t()
  def get_suite_run!(id) do
    repo().get!(SuiteRun, id)
  end

  @doc """
  Gets a suite run by ID for export.

  Preloads the suite, prompt version, and provider so the export
  payload can be built without leaking Repo access to the web layer.
  """
  @spec get_suite_run_for_export!(binary()) :: SuiteRun.t()
  def get_suite_run_for_export!(id) do
    SuiteRun
    |> repo().get!(id)
    |> repo().preload([:suite, :suite_policy, :prompt_version, :provider])
  end

  @doc """
  Reloads a suite run with associations preloaded.
  """
  @spec reload_suite_run_with_associations(SuiteRun.t()) :: SuiteRun.t()
  def reload_suite_run_with_associations(%SuiteRun{} = suite_run) do
    repo().preload(suite_run, [:suite_policy, :prompt_version, :provider], force: true)
  end

  @doc """
  Creates a new suite run.
  """
  @spec create_suite_run(map()) ::
          {:ok, SuiteRun.t()} | {:error, Changeset.t()}
  def create_suite_run(attrs \\ %{}) do
    %SuiteRun{}
    |> SuiteRun.changeset(attrs)
    |> repo().insert()
  end

  @doc """
  Deletes a suite run.
  """
  @spec delete_suite_run(SuiteRun.t()) ::
          {:ok, SuiteRun.t()} | {:error, Changeset.t()}
  def delete_suite_run(%SuiteRun{} = suite_run) do
    repo().delete(suite_run)
  end

  @doc """
  Retries a single test case result within an existing suite run.

  The existing embedded result is replaced in-place and the suite run
  aggregates are recalculated from the updated result set. Sampled results
  repeat their complete persisted sampling configuration. The run is refreshed
  before execution, and overlapping retries reject the stale write instead of
  replacing a newer result.
  """
  @spec retry_suite_run_test_case(SuiteRun.t(), binary()) ::
          {:ok, SuiteRun.t()} | {:error, term()}
  def retry_suite_run_test_case(%SuiteRun{} = suite_run, test_case_id)
      when is_binary(test_case_id) do
    with {:ok, suite_run} <- fetch_suite_run(suite_run.id),
         {:ok, existing_result} <- fetch_suite_run_result(suite_run, test_case_id),
         {:ok, sampling} <- Sampling.from_result(existing_result),
         {:ok, test_case} <- fetch_suite_test_case(suite_run.suite_id, test_case_id),
         {:ok, version} <- fetch_prompt_version(suite_run.prompt_version_id),
         {:ok, provider} <- fetch_provider(suite_run.provider_id) do
      retried_result =
        test_case
        |> execute_test_case(version, provider, sampling)
        |> merge_retry_metadata(existing_result)

      updated_results = replace_suite_run_result(suite_run.results, test_case_id, retried_result)
      summary = summarize_suite_results(updated_results)
      policy = suite_policy_for_run(suite_run)

      suite_run
      |> SuiteRun.changeset(
        summary
        |> Map.put(:results, updated_results)
        |> Map.merge(quality_policy_attrs(policy, updated_results, summary))
      )
      |> Changeset.optimistic_lock(:lock_version)
      |> repo().update()
    end
  rescue
    _error in Ecto.StaleEntryError ->
      {:error, :stale_suite_run}

    error ->
      {:error, {:retry_failed, Exception.message(error)}}
  catch
    kind, reason ->
      {:error, {:retry_failed, {kind, reason}}}
  end

  @doc """
  Executes a test suite against a prompt version and provider.

  Runs all test cases for the suite, evaluating their assertions
  against the LLM output and creating a suite run with results. When the suite
  has a quality policy, execution snapshots the latest immutable version before
  any model requests and persists its evaluation with the run.

  ## Parameters
    - suite: The test suite to execute
    - prompt_version: The prompt version to use
    - provider: The LLM provider to call
    - opts: Sampling options accepted by `Aludel.Evals.Sampling.new/1`

  ## Returns
    - `{:ok, suite_run}` with execution results
    - `{:error, reason}` if execution fails
  """
  @spec execute_suite(Suite.t(), PromptVersion.t(), Provider.t(), keyword()) ::
          {:ok, SuiteRun.t()} | {:error, term()}
  def execute_suite(
        %Suite{} = suite,
        %PromptVersion{} = version,
        %Provider{} = provider,
        opts \\ []
      ) do
    with {:ok, sampling} <- Sampling.new(opts) do
      suite = repo().preload(suite, test_cases: :documents)
      policy = latest_suite_policy(suite)

      results =
        Enum.map(suite.test_cases, &execute_test_case(&1, version, provider, sampling))

      summary = summarize_suite_results(results)

      create_suite_run(
        summary
        |> Map.merge(%{
          suite_id: suite.id,
          prompt_version_id: version.id,
          provider_id: provider.id,
          results: results
        })
        |> Map.merge(quality_policy_attrs(policy, results, summary))
      )
    end
  end

  @doc """
  Launches suite execution in a supervised task and reports completion
  back to the given recipient process. Sampling options are forwarded to the
  execution task.
  """
  @spec launch_suite_execution(pid(), binary(), binary(), binary(), keyword()) ::
          {:ok, reference()} | {:error, term()}
  def launch_suite_execution(recipient, suite_id, version_id, provider_id, opts \\ []) do
    case SuiteRunner.launch(recipient, suite_id, version_id, provider_id, opts) do
      {:ok, task_pid} -> {:ok, Process.monitor(task_pid)}
      {:error, reason} -> {:error, reason}
    end
  end

  # Test Case Document functions

  @doc """
  Creates a test case document.
  """
  @spec create_test_case_document(map()) ::
          {:ok, TestCaseDocument.t()} | {:error, Changeset.t()}
  def create_test_case_document(attrs \\ %{}) do
    document = %TestCaseDocument{id: Ecto.UUID.generate()}
    changeset = TestCaseDocument.create_changeset(document, attrs)

    if changeset.valid? do
      persist_document_externally(changeset)
    else
      {:error, changeset}
    end
  end

  @doc """
  Deletes a test case document.
  """
  @spec delete_test_case_document(TestCaseDocument.t()) ::
          {:ok, TestCaseDocument.t()} | {:error, Changeset.t()}
  def delete_test_case_document(%TestCaseDocument{} = document) do
    repo().transaction(fn ->
      with {:ok, deleted_document} <- repo().delete(document),
           :ok <- Storage.delete(document.storage_key, storage_backend: document.storage_backend) do
        deleted_document
      else
        {:error, %Changeset{} = changeset} ->
          repo().rollback({:document, changeset})

        {:error, reason} ->
          changeset = add_storage_error(Changeset.change(document), reason)
          repo().rollback({:storage, changeset})
      end
    end)
    |> case do
      {:ok, deleted_document} ->
        {:ok, deleted_document}

      {:error, {:document, changeset}} ->
        {:error, changeset}

      {:error, {:storage, changeset}} ->
        {:error, changeset}
    end
  end

  @doc """
  Gets a test case with documents preloaded.
  """
  @spec get_test_case_with_documents!(binary()) :: TestCase.t()
  def get_test_case_with_documents!(id) do
    TestCase
    |> repo().get!(id)
    |> repo().preload(:documents)
  end

  # Private functions

  defp execute_test_case(test_case, version, provider, %Sampling{samples: 1}) do
    execute_test_case_attempt(test_case, version, provider)
  end

  defp execute_test_case(test_case, version, provider, %Sampling{samples: samples} = sampling) do
    attempts =
      Enum.map(1..samples, fn _ ->
        execute_test_case_attempt(test_case, version, provider)
      end)

    Sampling.aggregate(attempts, sampling)
  end

  defp execute_test_case_attempt(test_case, version, provider) do
    test_case = ensure_documents_loaded(test_case)

    request = %{
      kind: :suite,
      prompt_version: version,
      variables: test_case.variable_values,
      messages: test_case.messages,
      provider: provider,
      documents: test_case.documents,
      metadata: %{
        suite_id: test_case.suite_id,
        suite_run_id: nil,
        test_case_id: test_case.id
      }
    }

    case Execution.execute_with_artifacts(request) do
      {:ok, result} ->
        metric_context = build_metric_context(test_case, version, provider, result)
        assertion_results = build_assertion_results(test_case.assertions, metric_context)
        passed = Enum.all?(assertion_results, & &1["passed"])
        score = AssertionEvaluator.score_for_results(assertion_results)
        artifacts = Artifact.put_metrics(result.artifacts, assertion_results, score)

        successful_test_case_result(
          test_case,
          result,
          passed,
          score,
          assertion_results,
          artifacts
        )

      {:error, reason, artifacts} ->
        failed_test_case_result(test_case, reason, artifacts)
    end
  end

  defp build_assertion_results(assertions, metric_context) do
    Enum.map(assertions, &AssertionEvaluator.evaluate(metric_context, &1))
  end

  defp build_metric_context(test_case, version, provider, result) do
    input = result.artifacts |> first_artifact_step() |> Map.get("input", %{})

    Context.new(result.output,
      rendered_input: input["rendered_prompt"],
      prompt_template: version.template,
      variables: test_case.variable_values,
      messages: Map.get(input, "messages", test_case.messages),
      documents: Map.get(input, "documents", []),
      metadata: test_case.metadata,
      provider: %{
        "id" => provider.id,
        "model" => provider.model,
        "type" => to_string(provider.provider)
      },
      prompt_version: %{
        "id" => version.id,
        "version" => version.version
      },
      execution: %{
        "input_tokens" => result.input_tokens,
        "output_tokens" => result.output_tokens,
        "cost_usd" => result.cost_usd,
        "latency_ms" => result.latency_ms,
        "metadata" => result.metadata
      }
    )
  end

  defp first_artifact_step(%{"steps" => [step | _remaining]}) when is_map(step) do
    step
  end

  defp first_artifact_step(_artifacts) do
    %{}
  end

  defp successful_test_case_result(
         test_case,
         result,
         passed,
         score,
         assertion_results,
         artifacts
       ) do
    %{
      "test_case_id" => test_case.id,
      "test_case_metadata" => test_case.metadata,
      "passed" => passed,
      "score" => score,
      "output" => result.output,
      "assertion_results" => assertion_results,
      "input_tokens" => result.input_tokens,
      "output_tokens" => result.output_tokens,
      "cost_usd" => result.cost_usd,
      "latency_ms" => result.latency_ms,
      "metadata" => result.metadata,
      "artifacts" => artifacts
    }
  end

  defp failed_test_case_result(test_case, reason, artifacts) do
    %{
      "test_case_id" => test_case.id,
      "test_case_metadata" => test_case.metadata,
      "passed" => false,
      "score" => nil,
      "output" => error_message(reason),
      "assertion_results" => [],
      "input_tokens" => nil,
      "output_tokens" => nil,
      "cost_usd" => nil,
      "latency_ms" => nil,
      "metadata" => nil,
      "artifacts" => artifacts
    }
  end

  defp error_message(:missing_api_key), do: "Missing API key"
  defp error_message(:executor_not_configured), do: "Callback executor not configured"
  defp error_message({:auth_error, msg}), do: "Authentication error: #{msg}"

  defp error_message({:rate_limit, retry_after}) do
    "Rate limit exceeded#{if retry_after, do: ", retry after #{retry_after}s", else: ""}"
  end

  defp error_message({:invalid_request, msg}), do: "Invalid request: #{msg}"
  defp error_message({:api_error, status, msg}), do: "API error (#{status}): #{msg}"
  defp error_message({:network_error, err}), do: "Network error: #{inspect(err)}"

  defp error_message({:document_storage_error, filename, reason}),
    do: "Failed to load document #{filename}: #{format_storage_reason(reason)}"

  defp error_message({:invalid_executor, module}),
    do: "Invalid callback executor: #{inspect(module)}"

  defp error_message({:invalid_executor_response, detail}),
    do: "Invalid callback response: #{inspect(detail)}"

  defp error_message(reason), do: inspect(reason)

  defp fetch_suite_run(suite_run_id) do
    case repo().get(SuiteRun, suite_run_id) do
      nil -> {:error, :suite_run_not_found}
      suite_run -> {:ok, suite_run}
    end
  end

  defp fetch_suite_run_result(%SuiteRun{results: results}, test_case_id) do
    case Enum.find(results, &(&1["test_case_id"] == test_case_id)) do
      nil -> {:error, :test_case_result_not_found}
      result -> {:ok, result}
    end
  end

  defp fetch_suite_test_case(suite_id, test_case_id) do
    query =
      from tc in TestCase,
        where: tc.id == ^test_case_id and tc.suite_id == ^suite_id

    case repo().one(query) do
      nil -> {:error, :test_case_not_found}
      test_case -> {:ok, repo().preload(test_case, :documents)}
    end
  end

  defp fetch_prompt_version(version_id) do
    case repo().get(PromptVersion, version_id) do
      nil -> {:error, :prompt_version_not_found}
      version -> {:ok, version}
    end
  end

  defp fetch_provider(provider_id) do
    case repo().get(Provider, provider_id) do
      nil -> {:error, :provider_not_found}
      provider -> {:ok, provider}
    end
  end

  defp merge_retry_metadata(result, existing_result) do
    retry_count = parse_retry_count(existing_result["retry_count"])

    Map.merge(result, %{
      "retry_count" => retry_count + 1,
      "retried_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    })
  end

  defp parse_retry_count(count) when is_integer(count), do: count

  defp parse_retry_count(count) when is_binary(count) do
    case Integer.parse(count) do
      {parsed, ""} -> parsed
      _ -> 0
    end
  end

  defp parse_retry_count(_count), do: 0

  defp replace_suite_run_result(results, test_case_id, replacement) do
    Enum.map(results, fn result ->
      if result["test_case_id"] == test_case_id, do: replacement, else: result
    end)
  end

  defp quality_policy_attrs(nil, _results, _summary) do
    %{suite_policy_id: nil, quality_policy_result: nil}
  end

  defp quality_policy_attrs(%SuitePolicy{} = policy, results, summary) do
    policy_result =
      policy.definition
      |> QualityPolicy.evaluate(results, summary)
      |> Map.put("policy_id", policy.id)
      |> Map.put("policy_version", policy.version)

    %{suite_policy_id: policy.id, quality_policy_result: policy_result}
  end

  defp suite_policy_for_run(%SuiteRun{suite_policy_id: nil}) do
    nil
  end

  defp suite_policy_for_run(%SuiteRun{suite_policy_id: policy_id}) do
    repo().get(SuitePolicy, policy_id)
  end

  defp lock_suite!(suite_id) do
    Suite
    |> where([suite], suite.id == ^suite_id)
    |> lock("FOR UPDATE")
    |> repo().one!()
  end

  defp next_suite_policy_version(suite_id) do
    SuitePolicy
    |> where([policy], policy.suite_id == ^suite_id)
    |> select([policy], max(policy.version))
    |> repo().one()
    |> Kernel.||(0)
    |> Kernel.+(1)
  end

  defp summarize_suite_results(results) do
    metrics =
      Enum.reduce(results, empty_summary_metrics(), fn result, acc ->
        acc
        |> accumulate_cost_and_latency(result)
        |> accumulate_score(result)
      end)

    passed = Enum.count(results, &(&1["passed"] == true))
    failed = length(results) - passed

    %{
      passed: passed,
      failed: failed,
      avg_cost_usd: average_cost(metrics),
      avg_latency_ms: average_latency(metrics),
      avg_score: average_score(metrics),
      total_cost_usd: total_cost(metrics),
      cost_sample_count: metrics.cost_samples,
      total_latency_ms: total_latency(metrics),
      latency_sample_count: metrics.latency_samples
    }
  end

  defp total_cost(%{cost_samples: 0}) do
    nil
  end

  defp total_cost(%{total_cost: total_cost}) do
    total_cost
  end

  defp total_latency(%{latency_samples: 0}) do
    nil
  end

  defp total_latency(%{total_latency: total_latency}) do
    total_latency
  end

  defp decimal_from_number(number) when is_float(number), do: Decimal.from_float(number)
  defp decimal_from_number(number) when is_integer(number), do: Decimal.new(number)

  defp average_cost(%{cost_samples: cost_samples}) when cost_samples < 1, do: nil

  defp average_cost(%{total_cost: total_cost, cost_samples: cost_samples}) do
    Decimal.div(total_cost, cost_samples)
  end

  defp average_latency(%{latency_samples: latency_samples}) when latency_samples < 1, do: nil

  defp average_latency(%{total_latency: total_latency, latency_samples: latency_samples}) do
    round(total_latency / latency_samples)
  end

  defp average_score(%{scored: scored}) when scored < 1, do: nil

  defp average_score(%{total_score: total_score, scored: scored}) do
    total_score
    |> Decimal.div(scored)
    |> Decimal.round(1)
  end

  defp empty_summary_metrics do
    %{
      total_cost: Decimal.new("0"),
      cost_samples: 0,
      total_latency: 0,
      latency_samples: 0,
      total_score: Decimal.new("0"),
      scored: 0
    }
  end

  defp accumulate_cost_and_latency(
         acc,
         %{"cost_usd" => cost, "latency_ms" => latency} = result
       ) do
    acc
    |> maybe_accumulate_cost(cost, sample_count(result, "cost_sample_count", cost))
    |> maybe_accumulate_latency(
      latency,
      sample_count(result, "latency_sample_count", latency)
    )
  end

  defp accumulate_cost_and_latency(acc, _result), do: acc

  defp maybe_accumulate_cost(acc, cost, sample_count)
       when is_number(cost) and is_integer(sample_count) and sample_count > 0 do
    %{
      acc
      | total_cost: Decimal.add(acc.total_cost, decimal_from_number(cost)),
        cost_samples: acc.cost_samples + sample_count
    }
  end

  defp maybe_accumulate_cost(acc, _cost, _sample_count) do
    acc
  end

  defp maybe_accumulate_latency(acc, latency, sample_count)
       when is_number(latency) and is_integer(sample_count) and sample_count > 0 do
    %{
      acc
      | total_latency: acc.total_latency + round(latency),
        latency_samples: acc.latency_samples + sample_count
    }
  end

  defp maybe_accumulate_latency(acc, _latency, _sample_count) do
    acc
  end

  defp sample_count(result, field, value) when is_number(value) do
    case Map.get(result, field) do
      count when is_integer(count) and count > 0 -> count
      _missing_or_invalid -> 1
    end
  end

  defp sample_count(_result, _field, _value) do
    0
  end

  defp accumulate_score(acc, %{"score" => score}) when is_number(score) do
    %{
      acc
      | total_score: Decimal.add(acc.total_score, decimal_from_number(score)),
        scored: acc.scored + 1
    }
  end

  defp accumulate_score(acc, _result), do: acc

  defp ensure_documents_loaded(%TestCase{documents: %NotLoaded{}} = test_case) do
    repo().preload(test_case, :documents)
  end

  defp ensure_documents_loaded(%TestCase{} = test_case), do: test_case

  defp repo, do: Aludel.Repo.get()

  defp persist_document_externally(changeset) do
    document = Changeset.apply_changes(changeset)
    storage_key = Storage.storage_key(document.id, document.filename)
    storage_backend = Storage.backend_name()

    case Storage.put(storage_key, document.data, document.content_type) do
      {:ok, persisted_key} ->
        attrs =
          document_attrs(document)
          |> Map.put(:data, nil)
          |> Map.put(:storage_key, persisted_key)
          |> Map.put(:storage_backend, storage_backend)

        insert_changeset = TestCaseDocument.changeset(%TestCaseDocument{id: document.id}, attrs)

        case repo().insert(insert_changeset) do
          {:ok, stored_document} ->
            {:ok, stored_document}

          {:error, insert_changeset} ->
            _ = Storage.delete(persisted_key, storage_backend: storage_backend)
            {:error, insert_changeset}
        end

      {:error, reason} ->
        {:error, add_storage_error(changeset, reason)}
    end
  end

  defp document_attrs(document) do
    %{
      test_case_id: document.test_case_id,
      filename: document.filename,
      content_type: document.content_type,
      data: document.data,
      size_bytes: document.size_bytes,
      storage_key: document.storage_key,
      storage_backend: document.storage_backend
    }
  end

  defp add_storage_error(changeset, reason) do
    Changeset.add_error(changeset, :data, format_storage_reason(reason))
  end

  defp format_storage_reason(reason) when is_binary(reason), do: reason
  defp format_storage_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_storage_reason(reason), do: inspect(reason)
end
