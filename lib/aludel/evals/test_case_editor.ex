defmodule Aludel.Evals.TestCaseEditor do
  @moduledoc """
  Coordinates suite test case editing workflows outside the web layer.
  """

  import Ecto.Changeset

  alias Aludel.Evals
  alias Aludel.Evals.AssertionParser
  alias Aludel.Evals.TestCase

  @default_assertions []
  @form_fields ~w(id variable_values assertions_json)a
  @form_types %{id: :string, variable_values: :map, assertions_json: :string}

  @doc """
  Creates an empty suite test case with variables derived from a prompt template.
  """
  @spec create_test_case(binary(), map()) ::
          {:ok, TestCase.t()} | {:error, Ecto.Changeset.t()}
  def create_test_case(suite_id, prompt) do
    variable_values =
      prompt
      |> prompt_template()
      |> extract_variables()
      |> Map.new(fn variable -> {variable, ""} end)

    Evals.create_test_case(%{
      suite_id: suite_id,
      variable_values: variable_values,
      assertions: @default_assertions
    })
  end

  @doc """
  Converts a test case into parameters shared by the visual and JSON editors.
  """
  @spec build_form_params(TestCase.t()) :: map()
  def build_form_params(%TestCase{} = test_case) do
    %{
      "id" => test_case.id,
      "variable_values" => test_case.variable_values || %{}
    }
    |> Map.merge(AssertionParser.build_form_params(test_case.assertions || []))
  end

  @doc """
  Builds the schemaless changeset used to validate the test-case editor form.

  Pass `:assertion_error` or `:action` in `opts` to surface assertion parsing
  failures or set the changeset action.
  """
  @spec change_form(TestCase.t() | map(), keyword()) :: Ecto.Changeset.t()
  def change_form(test_case_or_params, opts \\ [])

  def change_form(%TestCase{} = test_case, opts) do
    test_case
    |> build_form_params()
    |> change_form(opts)
  end

  def change_form(params, opts) when is_map(params) do
    {%{}, @form_types}
    |> cast(params, @form_fields)
    |> validate_required([:id])
    |> maybe_put_assertion_error(opts[:assertion_error])
    |> maybe_put_action(opts[:action])
  end

  @doc """
  Parses editor parameters and persists variables and assertions for a test case.
  """
  @spec update_test_case(TestCase.t(), map(), AssertionParser.parse_mode()) ::
          {:ok, TestCase.t()} | {:error, String.t()} | {:error, Ecto.Changeset.t()}
  def update_test_case(%TestCase{} = test_case, params, edit_mode) do
    variables = Map.get(params, "variable_values", %{})

    with {:ok, assertions} <- AssertionParser.parse(edit_mode, params) do
      Evals.update_test_case(test_case, %{variable_values: variables, assertions: assertions})
    end
  end

  defp prompt_template(%{versions: [%{template: template} | _]}), do: template
  defp prompt_template(_prompt), do: ""

  defp extract_variables(template) do
    ~r/\{\{([^}]+)\}\}/
    |> Regex.scan(template)
    |> Enum.map(fn [_, variable] -> String.trim(variable) end)
    |> Enum.uniq()
  end

  defp maybe_put_assertion_error(changeset, nil), do: changeset

  defp maybe_put_assertion_error(changeset, message),
    do: add_error(changeset, :assertions_json, message)

  defp maybe_put_action(changeset, nil), do: changeset
  defp maybe_put_action(changeset, action), do: Map.put(changeset, :action, action)
end
