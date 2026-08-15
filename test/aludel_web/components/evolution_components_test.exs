defmodule Aludel.Web.EvolutionComponentsTest do
  use Aludel.Web.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Aludel.Web.EvolutionComponents

  test "marks a pass-rate increase as an improvement" do
    document =
      render_component(&EvolutionComponents.metric_delta/1, metric: :pass_rate, delta: 30.0)
      |> LazyHTML.from_fragment()

    match =
      LazyHTML.filter(
        document,
        "[data-metric-delta='pass_rate'][data-delta-direction='improved']"
      )

    assert LazyHTML.to_html(match) =~ "+30.0 pp"
  end

  test "treats lower cost as an improvement and higher latency as a regression" do
    cost_document =
      render_component(&EvolutionComponents.metric_delta/1,
        metric: :cost_usd,
        delta: Decimal.new("-0.0020")
      )
      |> LazyHTML.from_fragment()

    latency_document =
      render_component(&EvolutionComponents.metric_delta/1, metric: :latency_ms, delta: 80)
      |> LazyHTML.from_fragment()

    improved_cost =
      LazyHTML.filter(
        cost_document,
        "[data-metric-delta='cost_usd'][data-delta-direction='improved']"
      )

    regressed_latency =
      LazyHTML.filter(
        latency_document,
        "[data-metric-delta='latency_ms'][data-delta-direction='regressed']"
      )

    assert LazyHTML.to_html(improved_cost) =~ "-$0.0020"
    assert LazyHTML.to_html(regressed_latency) =~ "+80 ms"
  end
end
