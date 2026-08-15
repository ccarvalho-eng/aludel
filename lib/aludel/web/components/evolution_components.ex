defmodule Aludel.Web.EvolutionComponents do
  @moduledoc false

  use Aludel.Web, :html

  attr :metric, :atom, required: true
  attr :delta, :any, default: nil
  attr :compact, :boolean, default: false

  def metric_delta(assigns) do
    assigns =
      assigns
      |> assign(:direction, delta_direction(assigns.metric, assigns.delta))
      |> assign(:icon, delta_icon(assigns.delta))
      |> assign(:label, delta_label(assigns.metric, assigns.delta))
      |> assign(:color, delta_color(delta_direction(assigns.metric, assigns.delta)))

    ~H"""
    <span
      :if={not is_nil(@delta)}
      data-metric-delta={@metric}
      data-delta-direction={@direction}
      style={"display: inline-flex; align-items: center; gap: 3px; margin-top: 4px; font-size: 11px; font-weight: 600; color: #{@color};"}
    >
      <.icon name={@icon} class="size-3" />
      {@label}<span :if={not @compact}>&nbsp;vs previous</span>
    </span>
    """
  end

  defp delta_direction(_metric, nil) do
    nil
  end

  defp delta_direction(metric, delta) when metric in [:cost_usd, :latency_ms] do
    delta
    |> numeric_value()
    |> lower_is_better_direction()
  end

  defp delta_direction(_metric, delta) do
    delta
    |> numeric_value()
    |> higher_is_better_direction()
  end

  defp lower_is_better_direction(value) when value < 0 do
    :improved
  end

  defp lower_is_better_direction(value) when value > 0 do
    :regressed
  end

  defp lower_is_better_direction(_value) do
    :unchanged
  end

  defp higher_is_better_direction(value) when value > 0 do
    :improved
  end

  defp higher_is_better_direction(value) when value < 0 do
    :regressed
  end

  defp higher_is_better_direction(_value) do
    :unchanged
  end

  defp delta_icon(nil) do
    "hero-minus-small"
  end

  defp delta_icon(delta) do
    case numeric_value(delta) do
      value when value > 0 -> "hero-arrow-trending-up"
      value when value < 0 -> "hero-arrow-trending-down"
      _value -> "hero-minus-small"
    end
  end

  defp delta_label(_metric, nil) do
    nil
  end

  defp delta_label(:pass_rate, delta) do
    value = numeric_value(delta)
    "#{sign(value)}#{format_number(abs(value), 1)} pp"
  end

  defp delta_label(:cost_usd, delta) do
    value = numeric_value(delta)
    "#{sign(value)}$#{format_number(abs(value), 4)}"
  end

  defp delta_label(:latency_ms, delta) do
    value = numeric_value(delta)
    "#{sign(value)}#{round(abs(value))} ms"
  end

  defp delta_color(:improved) do
    "#059669"
  end

  defp delta_color(:regressed) do
    "#dc2626"
  end

  defp delta_color(_direction) do
    "var(--text-muted)"
  end

  defp numeric_value(%Decimal{} = value) do
    Decimal.to_float(value)
  end

  defp numeric_value(value) do
    value
  end

  defp sign(value) when value > 0 do
    "+"
  end

  defp sign(value) when value < 0 do
    "-"
  end

  defp sign(_value) do
    ""
  end

  defp format_number(value, decimals) do
    :erlang.float_to_binary(value / 1, decimals: decimals)
  end
end
