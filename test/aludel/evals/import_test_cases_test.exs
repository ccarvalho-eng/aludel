defmodule Aludel.Evals.ImportTestCasesTest do
  use Aludel.DataCase, async: true

  alias Aludel.Evals

  describe "import_test_cases/2" do
    test "persists imported test cases in source order" do
      suite = suite_fixture()

      assert {:ok, test_cases} =
               Evals.import_test_cases(suite, [
                 test_case_attrs("first", "one"),
                 test_case_attrs("second", "two")
               ])

      assert Enum.map(test_cases, & &1.variable_values["input"]) == ["first", "second"]

      persisted_suite = Evals.get_suite_with_test_cases!(suite.id)

      assert persisted_suite.test_cases
             |> Enum.map(& &1.variable_values["input"])
             |> MapSet.new() == MapSet.new(["first", "second"])
    end

    test "rolls back the batch and reports the failing row" do
      suite = suite_fixture()

      invalid_attrs = %{
        variable_values: %{"input" => "invalid"},
        assertions: [%{"type" => "unsupported", "value" => "value"}]
      }

      assert {:error, %{row: 2, changeset: changeset}} =
               Evals.import_test_cases(suite, [
                 test_case_attrs("valid", "value"),
                 invalid_attrs
               ])

      refute changeset.valid?
      assert Evals.get_suite_with_test_cases!(suite.id).test_cases == []
    end

    test "ignores suite IDs supplied by imported attributes" do
      target_suite = suite_fixture()
      other_suite = suite_fixture()

      attrs =
        "target"
        |> test_case_attrs("value")
        |> Map.put(:suite_id, other_suite.id)
        |> Map.put("suite_id", other_suite.id)

      assert {:ok, [test_case]} = Evals.import_test_cases(target_suite, [attrs])
      assert test_case.suite_id == target_suite.id
      assert Evals.get_suite_with_test_cases!(other_suite.id).test_cases == []
    end

    test "returns a changeset error when the target suite was deleted" do
      suite = suite_fixture()
      assert {:ok, _deleted_suite} = Evals.delete_suite(suite)

      assert {:error, %{row: 1, changeset: changeset}} =
               Evals.import_test_cases(suite, [test_case_attrs("stale", "value")])

      assert "does not exist" in errors_on(changeset).suite_id
    end
  end

  defp test_case_attrs(input, expected) do
    %{
      variable_values: %{"input" => input},
      assertions: [%{"type" => "contains", "value" => expected}]
    }
  end
end
