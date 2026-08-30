defmodule Aludel.PromptsFixtures do
  @moduledoc """
  Test fixtures for creating prompts.
  """

  alias Aludel.Prompts.Optimization

  def prompt_fixture(attrs \\ %{}) do
    {:ok, prompt} =
      attrs
      |> Enum.into(%{
        name: "Sample Prompt",
        description: "A sample prompt",
        tags: ["sample"]
      })
      |> Aludel.Prompts.create_prompt()

    prompt
  end

  def prompt_fixture_with_version(attrs \\ %{}) do
    prompt = prompt_fixture(Map.drop(attrs, [:template]))
    template = Map.get(attrs, :template, "Hello {{world}}")

    {:ok, _version} = Aludel.Prompts.create_prompt_version(prompt, template)

    Aludel.Prompts.get_prompt_with_versions!(prompt.id)
  end

  def prompt_suggestion_fixture(attrs) do
    {:ok, suggestion} = Optimization.create_suggestion(attrs)
    suggestion
  end
end
