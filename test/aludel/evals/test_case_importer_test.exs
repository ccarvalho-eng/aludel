defmodule Aludel.Evals.TestCaseImporterTest do
  use ExUnit.Case, async: true

  alias Aludel.Evals.TestCaseImporter

  describe "parse_json/1" do
    test "parses valid JSON import rows" do
      payload =
        Jason.encode!([
          %{input: "hello", expected: "world", assertion: "contains"},
          %{input: "foo", expected: "bar", assertion: "exact"}
        ])

      assert {:ok, result} = TestCaseImporter.parse_json(payload)
      assert result.summary.created == 2
      assert result.summary.rejected == 0

      assert [
               %{"type" => "contains", "value" => "world"},
               %{"type" => "exact_match", "value" => "bar"}
             ] =
               result.summary.test_cases |> Enum.map(& &1.assertions) |> List.flatten()

      assert [%{"input" => "hello"}, %{"input" => "foo"}] =
               result.summary.test_cases |> Enum.map(& &1.variable_values)
    end

    test "reports invalid JSON" do
      assert {:error, "Invalid JSON payload"} = TestCaseImporter.parse_json("{invalid}")
    end

    test "rejects JSON payloads that are not arrays" do
      assert {:error, "JSON payload must be a list of objects"} =
               TestCaseImporter.parse_json(~s({"input":"hello"}))
    end

    test "reports nested JSON values as row-level errors" do
      payload =
        Jason.encode!([
          %{input: %{nested: "value"}, expected: "world", assertion: "contains"}
        ])

      assert {:ok, result} = TestCaseImporter.parse_json(payload)
      assert result.summary.created == 0
      assert result.summary.rejected == 1
      assert [%{row: 1, message: "input must be a string"}] = result.errors
    end

    test "reports scalar JSON rows as row-level errors" do
      payload = Jason.encode!(["invalid"])

      assert {:ok, result} = TestCaseImporter.parse_json(payload)
      assert result.summary.created == 0
      assert result.summary.rejected == 1

      assert [%{row: 1, message: "row must be an object with input, expected, and assertion"}] =
               result.errors
    end
  end

  describe "parse_csv/1" do
    test "parses valid CSV rows" do
      payload = "input,expected,assertion\nfirst,ok,contains\nsecond,ok,exact\n"

      assert {:ok, result} = TestCaseImporter.parse_csv(payload)
      assert result.summary.created == 2
      assert result.summary.rejected == 0

      assert [%{"input" => "first"}, %{"input" => "second"}] =
               result.summary.test_cases |> Enum.map(& &1.variable_values)
    end

    test "returns row-level errors" do
      payload = "input,expected,assertion\nbad,,contains\nfirst,ok,contains\n"

      assert {:ok, result} = TestCaseImporter.parse_csv(payload)
      assert result.summary.created == 1
      assert result.summary.rejected == 1
      assert [%{row: 2, message: "expected is required", payload: row_data}] = result.errors
      assert row_data["input"] == "bad"
    end

    test "rejects invalid assertion types" do
      payload = "input,expected,assertion\nfirst,ok,does-not-exist\n"

      assert {:ok, result} = TestCaseImporter.parse_csv(payload)
      assert result.summary.created == 0
      assert result.summary.rejected == 1
      assert [%{message: "Unsupported assertion 'does-not-exist'", row: 2}] = result.errors
    end

    test "reports malformed CSV without raising" do
      payload = "input,expected,assertion\n\"unterminated,ok,contains"

      assert {:error, "Invalid CSV payload"} = TestCaseImporter.parse_csv(payload)
    end

    test "reports invalid UTF-8 CSV without raising" do
      assert {:error, "Invalid CSV payload"} = TestCaseImporter.parse_csv(<<255>>)
    end

    test "copies retained fields out of the source CSV binary" do
      ignored_column = String.duplicate("x", 1_000_000)
      payload = "input,expected,assertion,notes\nfirst,ok,contains,#{ignored_column}\n"

      assert {:ok, result} = TestCaseImporter.parse_csv(payload)
      [test_case] = result.summary.test_cases
      input = test_case.variable_values["input"]

      assert :binary.referenced_byte_size(input) == byte_size(input)
    end
  end
end
