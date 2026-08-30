defmodule Aludel.Datasets.Params do
  @moduledoc false

  alias Aludel.Evals.MessageValidator

  @dataset_defaults %{
    "name" => "",
    "description" => "",
    "metadata_json" => "{}"
  }

  @entry_defaults %{
    "name" => "",
    "variable_values_json" => "{}",
    "messages_json" => "[]",
    "assertions_json" => "[]",
    "metadata_json" => "{}"
  }

  @spec dataset_defaults() :: map()
  def dataset_defaults do
    @dataset_defaults
  end

  @spec dataset_defaults(struct()) :: map()
  def dataset_defaults(dataset) do
    %{
      "name" => dataset.name,
      "description" => dataset.description || "",
      "metadata_json" => encode(dataset.metadata)
    }
  end

  @spec entry_defaults() :: map()
  def entry_defaults do
    @entry_defaults
  end

  @spec parse_dataset(map()) :: {:ok, map()} | {:error, keyword()}
  def parse_dataset(params) do
    metadata_result = decode_object(params["metadata_json"], :metadata_json)
    errors = required_name_errors(params) ++ json_errors([metadata_result])

    case {errors, metadata_result} do
      {[], {:ok, metadata}} ->
        {:ok,
         %{
           name: params["name"],
           description: blank_to_nil(params["description"]),
           metadata: metadata
         }}

      _other ->
        {:error, errors}
    end
  end

  @spec parse_entry(map()) :: {:ok, map()} | {:error, keyword()}
  def parse_entry(params) do
    results = [
      decode_object(params["variable_values_json"], :variable_values_json),
      decode_array(params["messages_json"], :messages_json),
      decode_array(params["assertions_json"], :assertions_json),
      decode_object(params["metadata_json"], :metadata_json)
    ]

    errors = required_name_errors(params) ++ json_errors(results)

    case {errors, results} do
      {[], [{:ok, variable_values}, {:ok, messages}, {:ok, assertions}, {:ok, metadata}]} ->
        case MessageValidator.validate(messages) do
          :ok ->
            {:ok,
             %{
               name: params["name"],
               variable_values: variable_values,
               messages: messages,
               assertions: assertions,
               metadata: metadata
             }}

          {:error, message} ->
            {:error, [messages_json: {message, []}]}
        end

      _other ->
        {:error, errors}
    end
  end

  @spec parse_metadata_filter(map()) :: {:ok, map()} | {:error, {atom(), tuple()}}
  def parse_metadata_filter(params) do
    decode_object(params["metadata_json"], :metadata_json)
  end

  defp decode_object(value, field) do
    decode_json(value, field, &is_map/1, "must be a JSON object")
  end

  defp decode_array(value, field) do
    decode_json(value, field, &is_list/1, "must be a JSON array")
  end

  defp decode_json(value, field, predicate, message) do
    case Jason.decode(value || "") do
      {:ok, decoded} ->
        if predicate.(decoded) do
          {:ok, decoded}
        else
          {:error, {field, {message, []}}}
        end

      _other ->
        {:error, {field, {message, []}}}
    end
  end

  defp required_name_errors(%{"name" => name}) when is_binary(name) do
    if String.trim(name) == "", do: [name: {"can't be blank", []}], else: []
  end

  defp required_name_errors(_params) do
    [name: {"can't be blank", []}]
  end

  defp json_errors(results) do
    Enum.flat_map(results, fn
      {:ok, _value} -> []
      {:error, error} -> [error]
    end)
  end

  defp blank_to_nil(value) when value in [nil, ""] do
    nil
  end

  defp blank_to_nil(value) do
    value
  end

  defp encode(value) do
    Jason.encode!(value, pretty: true)
  end
end
