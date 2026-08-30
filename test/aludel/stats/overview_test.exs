defmodule Aludel.Stats.OverviewTest do
  use Aludel.DataCase

  import Aludel.PromptsFixtures
  import Aludel.EvalsFixtures
  import Aludel.ProvidersFixtures

  alias Aludel.Evals.SuiteRun
  alias Aludel.Runs.Run
  alias Aludel.Stats.Overview

  describe "comparison_stats/1" do
    test "compares runs between current and previous periods" do
      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Template")

      inserted_at_previous =
        DateTime.utc_now() |> DateTime.add(-10, :day) |> DateTime.truncate(:second)

      for _ <- 1..2 do
        %Run{}
        |> Run.changeset(%{
          name: "Previous Run",
          prompt_version_id: version.id,
          variable_values: %{}
        })
        |> Ecto.Changeset.put_change(:inserted_at, inserted_at_previous)
        |> Ecto.Changeset.put_change(:updated_at, inserted_at_previous)
        |> Repo.insert!()
      end

      inserted_at_current =
        DateTime.utc_now() |> DateTime.add(-3, :day) |> DateTime.truncate(:second)

      for _ <- 1..3 do
        %Run{}
        |> Run.changeset(%{
          name: "Current Run",
          prompt_version_id: version.id,
          variable_values: %{}
        })
        |> Ecto.Changeset.put_change(:inserted_at, inserted_at_current)
        |> Ecto.Changeset.put_change(:updated_at, inserted_at_current)
        |> Repo.insert!()
      end

      stats = Overview.comparison_stats(7)

      assert stats.previous.total_runs == 2
      assert stats.current.total_runs == 3
      assert stats.trends.total_runs == :up
    end

    test "returns stable trend when runs are equal" do
      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Template")

      inserted_at_previous =
        DateTime.utc_now() |> DateTime.add(-10, :day) |> DateTime.truncate(:second)

      %Run{}
      |> Run.changeset(%{
        name: "Previous Run",
        prompt_version_id: version.id,
        variable_values: %{}
      })
      |> Ecto.Changeset.put_change(:inserted_at, inserted_at_previous)
      |> Ecto.Changeset.put_change(:updated_at, inserted_at_previous)
      |> Repo.insert!()

      inserted_at_current =
        DateTime.utc_now() |> DateTime.add(-3, :day) |> DateTime.truncate(:second)

      %Run{}
      |> Run.changeset(%{
        name: "Current Run",
        prompt_version_id: version.id,
        variable_values: %{}
      })
      |> Ecto.Changeset.put_change(:inserted_at, inserted_at_current)
      |> Ecto.Changeset.put_change(:updated_at, inserted_at_current)
      |> Repo.insert!()

      stats = Overview.comparison_stats(7)

      assert stats.previous.total_runs == 1
      assert stats.current.total_runs == 1
      assert stats.trends.total_runs == :stable
    end
  end

  describe "bounded quality and efficiency comparisons" do
    test "compares quality, cost, latency, efficiency, and stability in matching periods" do
      now = ~U[2026-08-30 12:00:00Z]
      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Template")
      suite = suite_fixture(%{prompt_id: prompt.id})
      provider = provider_fixture()

      insert_suite_run_at(suite, version, provider, DateTime.add(now, -2, :day), %{
        passed: 10,
        failed: 0,
        avg_cost_usd: Decimal.new("0.01"),
        avg_latency_ms: 200
      })

      insert_suite_run_at(suite, version, provider, DateTime.add(now, -3, :day), %{
        passed: 0,
        failed: 10,
        avg_cost_usd: Decimal.new("0.01"),
        avg_latency_ms: 200
      })

      insert_suite_run_at(suite, version, provider, DateTime.add(now, -10, :day), %{
        passed: 10,
        failed: 0,
        avg_cost_usd: Decimal.new("0.01"),
        avg_latency_ms: 100
      })

      stats = Overview.comparison_stats(7, now)

      assert stats.current.suite_runs == 2
      assert stats.current.pass_rate == 50.0
      assert stats.current.total_cost_usd == 0.2
      assert stats.current.avg_latency_ms == 200.0
      assert stats.current.cost_per_passed_test == 0.02
      assert stats.current.latency_per_passed_test == 400.0
      assert stats.current.pass_rate_stddev == 50.0
      assert stats.current.stability_sample_size == 2

      assert stats.previous.pass_rate == 100.0
      assert stats.previous.cost_per_passed_test == 0.01
      assert stats.previous.latency_per_passed_test == 100.0
      assert stats.comparison.regressions == [:quality, :cost, :latency]
      assert stats.comparison.stability == :volatile
    end

    test "represents zero-pass efficiency as unavailable" do
      now = ~U[2026-08-30 12:00:00Z]
      prompt = prompt_fixture()
      {:ok, version} = Aludel.Prompts.create_prompt_version(prompt, "Template")
      suite = suite_fixture(%{prompt_id: prompt.id})
      provider = provider_fixture()

      insert_suite_run_at(suite, version, provider, DateTime.add(now, -1, :day), %{
        passed: 0,
        failed: 4,
        avg_cost_usd: Decimal.new("0.02"),
        avg_latency_ms: 250
      })

      stats = Overview.comparison_stats(7, now)

      assert stats.current.efficiency_status == :no_passes
      assert stats.current.cost_per_passed_test == nil
      assert stats.current.latency_per_passed_test == nil
    end
  end

  defp insert_suite_run_at(suite, version, provider, inserted_at, attrs) do
    %SuiteRun{}
    |> SuiteRun.changeset(
      Map.merge(attrs, %{
        suite_id: suite.id,
        prompt_version_id: version.id,
        provider_id: provider.id
      })
    )
    |> Ecto.Changeset.put_change(:inserted_at, inserted_at)
    |> Ecto.Changeset.put_change(:updated_at, inserted_at)
    |> Repo.insert!()
  end
end
