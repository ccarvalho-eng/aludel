defmodule Aludel.Evals.Reporters.JSON do
  @moduledoc """
  Renders the versioned evaluation report as JSON.

  Pass `pretty: true` to make the output easier to read. The compact encoding
  is deterministic at the schema level, but consumers must not depend on JSON
  object key order.
  """

  @behaviour Aludel.Evals.Reporter

  alias Aludel.Evals.Report

  @impl true
  def render(%Report{} = report, options) do
    {:ok, Jason.encode!(Report.to_map(report), pretty: Keyword.get(options, :pretty, false))}
  end
end
