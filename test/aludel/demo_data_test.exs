defmodule Aludel.DemoDataTest do
  use Aludel.DataCase, async: false

  import Ecto.Query

  alias Aludel.Datasets.{Dataset, DatasetEntry}
  alias Aludel.DemoData
  alias Aludel.Evals.{Suite, SuiteRun, TestCase}
  alias Aludel.Projects
  alias Aludel.Projects.Project
  alias Aludel.Prompts.{Evolution, Prompt, PromptVersion}
  alias Aludel.Providers.Provider
  alias Aludel.Runs.{Run, RunResult}
  alias Aludel.Stats.{Activity, Costs, Latency, Overview}

  @expected_summary %{
    projects: 4,
    providers: 14,
    prompts: 8,
    prompt_versions: 24,
    datasets: 6,
    dataset_entries: 72,
    suites: 8,
    test_cases: 96,
    runs: 150,
    run_results: 450,
    suite_runs: 150,
    suite_results: 1_800
  }

  test "seeds a complete, repeatable demo corpus without changing user records" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    {:ok, user_project} = Projects.create_project(%{name: "User-owned project", type: :prompt})

    assert {:ok, @expected_summary} = DemoData.run(repo: Repo, env: :test, now: now)

    first_ids = demo_ids()
    assert_demo_counts()
    assert_history_invariants(now)
    assert_dashboard_and_evolution_data(now)

    assert {:ok, @expected_summary} = DemoData.run(repo: Repo, env: :test, now: now)

    assert demo_ids() == first_ids
    assert_demo_counts()
    assert Repo.get!(Project, user_project.id).name == "User-owned project"
  end

  test "refuses to seed production" do
    assert {:error, :production_seed_disabled} =
             DemoData.run(repo: Repo, env: :prod, now: DateTime.utc_now())

    assert Repo.aggregate(Project, :count) == 0
  end

  defp assert_demo_counts do
    assert demo_count(Project) == 4
    assert demo_count(Provider) == 14
    assert demo_count(Prompt) == 8
    assert associated_count(PromptVersion, Prompt, :prompt_id) == 24
    assert demo_count(Dataset) == 6
    assert associated_count(DatasetEntry, Dataset, :dataset_id) == 72
    assert demo_count(Suite) == 8
    assert associated_count(TestCase, Suite, :suite_id) == 96
    assert demo_count(Run) == 150
    assert associated_count(RunResult, Run, :run_id) == 450
    assert associated_count(SuiteRun, Suite, :suite_id) == 150
    assert_expanded_providers_participate()
  end

  defp assert_expanded_providers_participate do
    provider_types = [:xai, :groq, :openrouter]

    run_provider_types =
      RunResult
      |> join(:inner, [result], run in Run, on: run.id == result.run_id)
      |> join(:inner, [result, _run], provider in Provider, on: provider.id == result.provider_id)
      |> where([_result, run], like(run.name, "Demo · %"))
      |> distinct(true)
      |> select([_result, _run, provider], provider.provider)
      |> Repo.all()

    suite_provider_types =
      SuiteRun
      |> join(:inner, [suite_run], suite in Suite, on: suite.id == suite_run.suite_id)
      |> join(:inner, [suite_run, _suite], provider in Provider,
        on: provider.id == suite_run.provider_id
      )
      |> where([_suite_run, suite], like(suite.name, "Demo · %"))
      |> distinct(true)
      |> select([_suite_run, _suite, provider], provider.provider)
      |> Repo.all()

    assert Enum.all?(provider_types, &(&1 in run_provider_types))
    assert Enum.all?(provider_types, &(&1 in suite_provider_types))
  end

  defp assert_history_invariants(now) do
    runs =
      Run
      |> where([run], like(run.name, "Demo · %"))
      |> preload(:run_results)
      |> Repo.all()

    assert Enum.all?(runs, &terminal_run?/1)
    assert Enum.all?(runs, &(DateTime.compare(&1.completed_at, &1.started_at) in [:eq, :gt]))
    assert Enum.all?(runs, &(DateTime.compare(&1.inserted_at, now) == :lt))

    suite_runs =
      SuiteRun
      |> join(:inner, [suite_run], suite in Suite, on: suite.id == suite_run.suite_id)
      |> where([_suite_run, suite], like(suite.name, "Demo · %"))
      |> Repo.all()

    assert Enum.all?(suite_runs, &suite_run_consistent?/1)
    assert Enum.all?(suite_runs, &(length(&1.results) == 12))
    assert Enum.all?(suite_runs, &valid_artifacts?/1)
  end

  defp assert_dashboard_and_evolution_data(now) do
    comparisons = Overview.rolling_comparisons(now)

    assert comparisons[7].current.total_runs > 0
    assert comparisons[7].previous.total_runs > 0
    assert comparisons[30].current.total_runs > 0
    assert comparisons[30].previous.total_runs > 0
    assert Enum.sum(Enum.map(Activity.daily_activity(30), & &1.total)) > 0
    assert Costs.cost_by_provider() != []
    assert Latency.latency_by_provider() != []

    prompt =
      Prompt
      |> join(:inner, [prompt], suite in Suite, on: suite.prompt_id == prompt.id)
      |> where([prompt], like(prompt.name, "Demo · %"))
      |> order_by([prompt], asc: prompt.name)
      |> select([prompt], prompt)
      |> limit(1)
      |> Repo.one!()

    metrics = Evolution.get_metrics(prompt.id, as_of: now, days: 60)
    assert length(metrics) == 3
    assert Enum.any?(metrics, &(&1.total_runs > 0))
  end

  defp terminal_run?(run) do
    statuses = Enum.map(run.run_results, & &1.status)

    case run.status do
      :completed -> Enum.all?(statuses, &(&1 == :completed))
      :failed -> Enum.all?(statuses, &(&1 == :error))
      :partial_failure -> :completed in statuses and :error in statuses
      _other -> false
    end
  end

  defp suite_run_consistent?(suite_run) do
    costs = suite_run.results |> Enum.map(& &1["cost_usd"]) |> Enum.filter(&is_number/1)
    latencies = suite_run.results |> Enum.map(& &1["latency_ms"]) |> Enum.filter(&is_number/1)
    passed = Enum.count(suite_run.results, &(&1["passed"] == true))

    suite_run.passed == passed and
      suite_run.failed == length(suite_run.results) - passed and
      suite_run.cost_sample_count == length(costs) and
      suite_run.latency_sample_count == length(latencies) and
      suite_run.total_latency_ms == Enum.sum(latencies) and
      Decimal.equal?(suite_run.total_cost_usd, decimal_sum(costs))
  end

  defp valid_artifacts?(suite_run) do
    Enum.all?(suite_run.results, fn result ->
      match?(%{"schema_version" => 1, "steps" => [_step]}, result["artifacts"])
    end)
  end

  defp decimal_sum(values) do
    Enum.reduce(values, Decimal.new("0"), fn value, total ->
      Decimal.add(total, Decimal.from_float(value))
    end)
  end

  defp demo_ids do
    %{
      prompts: demo_entity_ids(Prompt),
      datasets: demo_entity_ids(Dataset),
      suites: demo_entity_ids(Suite),
      runs: demo_entity_ids(Run),
      suite_runs: associated_ids(SuiteRun, Suite, :suite_id)
    }
  end

  defp demo_entity_ids(schema) do
    schema
    |> where([entity], like(entity.name, "Demo · %"))
    |> order_by([entity], asc: entity.id)
    |> select([entity], entity.id)
    |> Repo.all()
  end

  defp associated_ids(schema, owner, foreign_key) do
    schema
    |> join(:inner, [entity], owner in ^owner, on: field(entity, ^foreign_key) == owner.id)
    |> where([_entity, owner], like(owner.name, "Demo · %"))
    |> order_by([entity], asc: entity.id)
    |> select([entity], entity.id)
    |> Repo.all()
  end

  defp demo_count(schema) do
    schema
    |> where([entity], like(entity.name, "Demo · %"))
    |> Repo.aggregate(:count)
  end

  defp associated_count(schema, owner, foreign_key) do
    schema
    |> join(:inner, [entity], owner in ^owner, on: field(entity, ^foreign_key) == owner.id)
    |> where([_entity, owner], like(owner.name, "Demo · %"))
    |> Repo.aggregate(:count)
  end
end
