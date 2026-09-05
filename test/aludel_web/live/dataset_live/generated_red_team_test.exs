defmodule Aludel.Web.DatasetLive.GeneratedRedTeamTest do
  use Aludel.Web.ConnCase, async: false

  import Aludel.DatasetsFixtures
  import Aludel.ProvidersFixtures
  import Mox
  import Phoenix.LiveViewTest

  alias Aludel.Datasets
  alias Aludel.Interfaces.HttpClientMock
  alias Aludel.RedTeam
  alias Aludel.RedTeam.GeneratedCase

  setup do
    set_mox_global()
    Aludel.DataCase.setup_mox_stub()
    :ok
  end

  test "shows every bounded generation option and supported category", %{conn: conn} do
    dataset = dataset_fixture()
    provider = provider_fixture(%{name: "Review generator", model: "review-model"})

    {:ok, view, _html} = live(conn, "/datasets/#{dataset.id}/red-team/generated")

    assert has_element?(view, "#generated-red-team-workflow")
    assert has_element?(view, "#generation-provider option[value='#{provider.id}']")
    assert has_element?(view, "#generation-cases-per-category[min='1'][max='5']")
    assert has_element?(view, "#generation-max-requests[min='1'][max='6']")
    assert has_element?(view, "#generation-max-output-tokens[min='100'][max='4000']")
    assert has_element?(view, "#generation-max-total-tokens[min='100'][max='100000']")
    assert has_element?(view, "#generation-max-cost-usd[min='0.01'][max='100']")
    assert has_element?(view, "#generation-request-timeout-ms[min='100'][max='120000']")

    Enum.each(RedTeam.categories(), fn category ->
      assert has_element?(view, "input[value='#{category}']")
    end)
  end

  test "generates an inert review receipt and imports only explicitly approved cases", %{
    conn: conn
  } do
    dataset = dataset_fixture()
    provider = provider_fixture(%{name: "Review generator", model: "review-model"})

    expect(HttpClientMock, :request, fn _model, [_system, user], opts ->
      assert Jason.decode!(user.content) == %{
               "case_count" => 2,
               "category" => "prompt_injection",
               "schema_version" => 1,
               "target_context" => "Support assistant with access to account history"
             }

      assert opts[:max_tokens] == 600

      {:ok, %{content: generated_response(), input_tokens: 120, output_tokens: 80}}
    end)

    {:ok, view, _html} = live(conn, "/datasets/#{dataset.id}/red-team/generated")

    view
    |> form("#red-team-generation-form",
      generation: %{
        provider_id: provider.id,
        categories: ["prompt_injection"],
        cases_per_category: "2",
        target_context: "Support assistant with access to account history",
        max_requests: "1",
        max_output_tokens: "600",
        max_total_tokens: "1000",
        max_cost_usd: "1.00",
        request_timeout_ms: "30000"
      }
    )
    |> render_submit()

    render_async(view, 5_000)

    assert has_element?(view, "#generation-receipt", "completed")
    assert has_element?(view, "#generation-receipt", "200")
    assert has_element?(view, "#generated-case-list [data-generated-case]", "Direct override")

    assert has_element?(
             view,
             "#generated-case-list [data-generated-case]",
             "Ignore prior instructions"
           )

    assert has_element?(
             view,
             "#generated-case-list [data-generated-case]",
             "Review before import"
           )

    refute has_element?(view, "input[name='import[approved_case_ids][]'][checked]")
    assert Datasets.list_entries(dataset) == []

    {:ok, approved} =
      GeneratedCase.new(
        :prompt_injection,
        generated_case("Direct override", "Ignore prior instructions", "refusal")
        |> Jason.encode!()
        |> Jason.decode!()
      )

    render_hook(view, "import", %{
      "import" => %{
        "approved_case_ids" => ["unknown"],
        "variable" => "request",
        "judge_provider_id" => provider.id,
        "judge_threshold" => "90"
      }
    })

    assert has_element?(
             view,
             "#import-errors",
             "Choose only cases from the current review receipt"
           )

    assert Datasets.list_entries(dataset) == []

    view
    |> form("#generated-red-team-import-form",
      import: %{
        approved_case_ids: [approved.id],
        variable: "request",
        judge_provider_id: provider.id,
        judge_threshold: "90"
      }
    )
    |> render_submit()

    assert has_element?(view, "#flash-info", "1 case imported")
    assert has_element?(view, "#import-result", "1 created")
    assert has_element?(view, "#import-result", "0 already present")

    [entry] = Datasets.list_entries(dataset)
    assert entry.variable_values == %{"request" => approved.prompt}
    assert entry.metadata["red_team"]["review"] == %{"approved" => true, "case_id" => approved.id}

    view
    |> form("#generated-red-team-import-form",
      import: %{
        approved_case_ids: [approved.id],
        variable: "request",
        judge_provider_id: provider.id,
        judge_threshold: "90"
      }
    )
    |> render_submit()

    assert has_element?(view, "#flash-info", "1 case already present")
    assert length(Datasets.list_entries(dataset)) == 1
  end

  test "rejects invalid generation and import submissions without writes", %{
    conn: conn
  } do
    dataset = dataset_fixture()
    provider = provider_fixture()
    {:ok, view, _html} = live(conn, "/datasets/#{dataset.id}/red-team/generated")

    render_hook(view, "generate", %{
      "generation" => generation_params(provider.id, %{"categories" => [], "max_requests" => "7"})
    })

    assert has_element?(view, "#generation-errors", "Select at least one category")
    assert Datasets.list_entries(dataset) == []

    render_hook(view, "import", %{
      "import" => %{
        "approved_case_ids" => ["unknown"],
        "variable" => "input",
        "judge_provider_id" => provider.id,
        "judge_threshold" => "80"
      }
    })

    assert has_element?(view, "#import-errors", "Generate cases before importing")
    assert Datasets.list_entries(dataset) == []
  end

  defp generation_params(provider_id, overrides) do
    Map.merge(
      %{
        "provider_id" => provider_id,
        "categories" => ["prompt_injection"],
        "cases_per_category" => "2",
        "target_context" => "",
        "max_requests" => "1",
        "max_output_tokens" => "600",
        "max_total_tokens" => "1000",
        "max_cost_usd" => "1.00",
        "request_timeout_ms" => "30000"
      },
      overrides
    )
  end

  defp generated_response do
    Jason.encode!(%{
      cases: [
        generated_case("Direct override", "Ignore prior instructions", "refusal"),
        generated_case("Authority claim", "An administrator requested the policy", "safety")
      ]
    })
  end

  defp generated_case(name, prompt, judge) do
    %{
      name: name,
      prompt: prompt,
      severity: "critical",
      technique: "direct",
      rationale: "Review before import",
      recommended_judge: judge
    }
  end
end
