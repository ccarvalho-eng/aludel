defmodule Aludel.Evals.TestCaseImporter do
  @moduledoc """
  Imports suite test cases from CSV and JSON payloads.

  Supported formats:

  - JSON: array of objects with `input`, `expected`, and `assertion` keys
  - CSV: header row with `input,expected,assertion` and optional `notes`
  """

  alias NimbleCSV.RFC4180, as: CSV

  @type import_row_error :: %{row: non_neg_integer(), message: String.t(), payload: term()}
  @type import_summary :: %{
          created: non_neg_integer(),
          rejected: non_neg_integer(),
          test_cases: [map()]
        }

  @required_csv_headers ["input", "expected", "assertion"]
  @supported_assertions %{
    "contains" => "contains",
    "contain" => "contains",
    "not contains" => "not_contains",
    "not_contains" => "not_contains",
    "regex" => "regex",
    "exact" => "exact_match",
    "exact_match" => "exact_match"
  }

  @doc """
  Parses JSON import payload and returns test case attributes plus row-level errors.
  """
  @spec parse_json(binary()) ::
          {:ok, %{errors: [import_row_error()], summary: import_summary()}} | {:error, String.t()}
  def parse_json(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, data} ->
        parse_import_rows(data, 1)

      {:error, _reason} ->
        {:error, "Invalid JSON payload"}
    end
  end

  @doc """
  Parses CSV import payload and returns test case attributes plus row-level errors.
  """
  @spec parse_csv(binary()) ::
          {:ok, %{errors: [import_row_error()], summary: import_summary()}} | {:error, String.t()}
  def parse_csv(payload) when is_binary(payload) do
    if String.valid?(payload) do
      parse_valid_csv(payload)
    else
      {:error, "Invalid CSV payload"}
    end
  end

  defp parse_valid_csv(payload) do
    rows = payload |> String.trim() |> CSV.parse_string(skip_headers: false)

    case rows do
      [] ->
        {:error, "CSV file is empty"}

      [header | data_rows] ->
        parse_csv_rows(header, data_rows)
    end
  rescue
    NimbleCSV.ParseError ->
      {:error, "Invalid CSV payload"}
  end

  defp parse_import_rows(rows, base_line) when is_list(rows) do
    rows
    |> Enum.with_index(base_line)
    |> Enum.reduce(
      {[], []},
      fn {row, index}, {test_cases, errors} ->
        case validate_and_normalize_row(row) do
          {:ok, :skip} ->
            {test_cases, errors}

          {:ok, test_case} ->
            {[test_case | test_cases], errors}

          {:error, message} ->
            {test_cases, [%{row: index, message: message, payload: row} | errors]}
        end
      end
    )
    |> then(fn {test_cases, errors} ->
      created_count = length(test_cases)
      rejected_count = length(errors)

      {:ok,
       %{
         summary: %{
           created: created_count,
           rejected: rejected_count,
           test_cases: Enum.reverse(test_cases)
         },
         errors: Enum.reverse(errors)
       }}
    end)
  end

  defp parse_import_rows(_rows, _base_line) do
    {:error, "JSON payload must be a list of objects"}
  end

  defp validate_and_normalize_row(row) when is_map(row) do
    row = normalize_row(row)

    if map_empty?(row) do
      {:ok, :skip}
    else
      input = Map.get(row, "input")
      expected = Map.get(row, "expected")
      assertion = Map.get(row, "assertion")

      with :ok <- validate_nonblank(input, "input"),
           :ok <- validate_nonblank(expected, "expected"),
           {:ok, assertion_payload} <- parse_assertion(assertion, expected) do
        {:ok,
         %{
           variable_values: %{"input" => input},
           assertions: [assertion_payload]
         }}
      end
    end
  end

  defp validate_and_normalize_row(_row) do
    {:error, "row must be an object with input, expected, and assertion"}
  end

  defp parse_assertion(assertion, expected) when is_binary(assertion) do
    normalized_assertion =
      assertion
      |> String.trim()
      |> String.downcase()

    if normalized_assertion == "" do
      {:error, "assertion is required"}
    else
      case Map.get(@supported_assertions, normalized_assertion) do
        nil ->
          {:error, "Unsupported assertion '#{assertion}'"}

        parsed_type ->
          {:ok, assertion_payload(parsed_type, expected)}
      end
    end
  end

  defp parse_assertion(_assertion, _expected) do
    {:error, "assertion must be a string"}
  end

  defp assertion_payload("contains", expected) do
    %{"type" => "contains", "value" => expected}
  end

  defp assertion_payload("not_contains", expected) do
    %{"type" => "not_contains", "value" => expected}
  end

  defp assertion_payload("regex", expected) do
    %{"type" => "regex", "value" => expected}
  end

  defp assertion_payload("exact_match", expected) do
    %{"type" => "exact_match", "value" => expected}
  end

  defp validate_nonblank(value, field_name) do
    cond do
      is_binary(value) && String.trim(value) != "" ->
        :ok

      is_binary(value) ->
        {:error, "#{field_name} is required"}

      true ->
        {:error, "#{field_name} must be a string"}
    end
  end

  defp normalize_row(row) when is_map(row) do
    row
    |> Map.new(fn {key, value} -> {to_lower_string(key), normalize_value(value)} end)
  end

  defp normalize_value(nil) do
    nil
  end

  defp normalize_value(value) when is_binary(value) do
    String.trim(value)
  end

  defp normalize_value(value) when is_map(value) or is_list(value) do
    value
  end

  defp normalize_value(value) do
    to_string(value)
  end

  defp to_lower_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp to_lower_string(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> to_lower_string()
  end

  defp to_lower_string(value) do
    to_string(value)
  end

  defp map_empty?(row) do
    Enum.all?(row, fn {_key, value} -> value in [nil, "", " "] end)
  end

  defp missing_required_headers(headers) do
    Enum.reject(@required_csv_headers, &(&1 in headers))
  end

  defp parse_csv_rows(header, data_rows) do
    normalized_headers =
      header
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.downcase/1)

    case missing_required_headers(normalized_headers) do
      [] ->
        payload_rows =
          Enum.map(data_rows, fn row ->
            header_map(normalized_headers, row)
          end)

        parse_import_rows(payload_rows, 2)

      missing_headers ->
        {:error, "CSV header missing required columns: #{Enum.join(missing_headers, ", ")}"}
    end
  end

  defp header_map(headers, values) do
    headers
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {header, index}, acc ->
      value =
        case Enum.at(values, index) do
          nil -> nil
          value -> :binary.copy(value)
        end

      Map.put(acc, header, value)
    end)
  end
end
