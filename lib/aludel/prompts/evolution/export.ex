defmodule Aludel.Prompts.Evolution.Export do
  @moduledoc """
  Export serialization for prompt evolution metrics.
  """

  alias Aludel.Prompts.Prompt
  alias Decimal

  @doc """
  Serializes evolution metrics to JSON format.

  Returns a map with prompt metadata and evolution metrics including
  version history, performance data, and provider breakdowns.
  """
  @spec to_json(Prompt.t(), [map()]) :: map()
  def to_json(prompt, metrics) do
    %{
      type: "prompt_evolution",
      exported_at: iso8601(DateTime.utc_now()),
      prompt: %{
        id: prompt.id,
        name: prompt.name,
        description: prompt.description,
        tags: prompt.tags
      },
      metrics:
        Enum.map(metrics, fn metric ->
          %{
            version_id: metric.version_id,
            version_number: metric.version_number,
            created_at: iso8601(metric.created_at),
            total_runs: metric.total_runs,
            avg_pass_rate: metric.avg_pass_rate,
            avg_score: decimal_to_float(metric.avg_score),
            avg_cost_usd: decimal_to_float(metric.avg_cost_usd),
            avg_latency_ms: metric.avg_latency_ms,
            provider_breakdown:
              Enum.map(metric.provider_breakdown, fn breakdown ->
                %{
                  provider_id: breakdown.provider_id,
                  provider_name: breakdown.provider_name,
                  runs: breakdown.runs,
                  avg_pass_rate: breakdown.avg_pass_rate,
                  avg_score: decimal_to_float(breakdown.avg_score),
                  avg_cost_usd: decimal_to_float(breakdown.avg_cost_usd),
                  avg_latency_ms: breakdown.avg_latency_ms
                }
              end)
          }
        end)
    }
  end

  @doc """
  Serializes evolution metrics to CSV format.

  Returns a CSV string with headers and one row per version-provider combination.
  """
  @spec to_csv([map()]) :: String.t()
  def to_csv(metrics) do
    header =
      "version,created_at,total_runs,avg_pass_rate,avg_score,avg_cost_usd,avg_latency_ms,provider_name,provider_runs,provider_pass_rate,provider_score,provider_cost_usd,provider_latency_ms\n"

    rows =
      metrics
      |> Enum.flat_map(fn metric ->
        if Enum.empty?(metric.provider_breakdown) do
          [
            csv_row([
              metric.version_number,
              format_datetime(metric.created_at),
              metric.total_runs,
              format_number(metric.avg_pass_rate),
              format_number(decimal_to_float(metric.avg_score)),
              format_number(decimal_to_float(metric.avg_cost_usd)),
              format_number(metric.avg_latency_ms),
              "",
              "",
              "",
              "",
              "",
              ""
            ])
          ]
        else
          Enum.map(metric.provider_breakdown, fn breakdown ->
            csv_row([
              metric.version_number,
              format_datetime(metric.created_at),
              metric.total_runs,
              format_number(metric.avg_pass_rate),
              format_number(decimal_to_float(metric.avg_score)),
              format_number(decimal_to_float(metric.avg_cost_usd)),
              format_number(metric.avg_latency_ms),
              breakdown.provider_name,
              breakdown.runs,
              format_number(breakdown.avg_pass_rate),
              format_number(decimal_to_float(breakdown.avg_score)),
              format_number(decimal_to_float(breakdown.avg_cost_usd)),
              format_number(breakdown.avg_latency_ms)
            ])
          end)
        end
      end)
      |> Enum.join("\n")

    header <> rows
  end

  defp csv_row(values) when is_list(values) do
    Enum.map_join(values, ",", &csv_field/1)
  end

  defp csv_field(nil), do: ""
  defp csv_field(value) when not is_binary(value), do: to_string(value)

  defp csv_field(value) do
    value = neutralize_spreadsheet_formula(value)
    escaped = String.replace(value, "\"", "\"\"")

    if String.contains?(value, [",", "\"", "\n", "\r"]) do
      ~s("#{escaped}")
    else
      escaped
    end
  end

  defp neutralize_spreadsheet_formula(value) do
    if String.starts_with?(String.trim_leading(value), ["=", "+", "-", "@", "\t", "\r"]) do
      "'" <> value
    else
      value
    end
  end

  defp format_number(nil), do: ""
  defp format_number(num) when is_float(num), do: :erlang.float_to_binary(num, decimals: 4)
  defp format_number(num), do: num

  defp format_datetime(nil), do: ""
  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp decimal_to_float(nil), do: nil
  defp decimal_to_float(%Decimal{} = decimal), do: Decimal.to_float(decimal)

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
