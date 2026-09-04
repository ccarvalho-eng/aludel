defmodule Aludel.Evals.JudgeCatalogTest do
  use ExUnit.Case, async: true

  alias Aludel.Evals.JudgeCatalog

  test "lists the stable built-in judge IDs" do
    assert JudgeCatalog.ids() == [
             "correctness",
             "relevance",
             "faithfulness",
             "safety",
             "refusal",
             "pii",
             "hallucination"
           ]
  end

  test "returns versioned judge templates" do
    assert {:ok, template} = JudgeCatalog.fetch("faithfulness")
    assert template.id == "faithfulness"
    assert template.name == "Faithfulness"
    assert template.version == 1
    assert is_binary(template.description)
    assert is_binary(template.rubric)
    assert template.rubric =~ "grounding"
  end

  test "rejects unknown template IDs" do
    assert :error = JudgeCatalog.fetch("unknown")
    assert :error = JudgeCatalog.fetch(nil)
  end
end
