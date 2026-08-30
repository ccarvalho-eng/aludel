defmodule Mix.Tasks.Aludel.Seed do
  @moduledoc """
  Runs Aludel seed data.

  ## Usage

      mix aludel.seed

  This task populates a development database with deterministic demo data,
  including datasets, realistic AI outputs, individual runs, suite runs,
  evaluation metrics, and prompt evolution history.
  """

  use Mix.Task

  @shortdoc "Runs Aludel seed data"

  @impl Mix.Task
  def run(_args) do
    if Mix.env() == :prod do
      Mix.raise("mix aludel.seed is disabled in production")
    end

    Mix.Task.run("app.start")

    seeds_path = Path.join(:code.priv_dir(:aludel), "repo/seeds.exs")

    if File.exists?(seeds_path) do
      Code.eval_file(seeds_path)
    else
      Mix.shell().error("Seeds file not found at #{seeds_path}")
    end
  end
end
