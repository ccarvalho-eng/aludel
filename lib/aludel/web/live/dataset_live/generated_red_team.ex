defmodule Aludel.Web.DatasetLive.GeneratedRedTeam do
  @moduledoc """
  LiveView for generating, reviewing, and importing product-specific red-team cases.
  """

  use Aludel.Web, :live_view

  alias Aludel.Datasets
  alias Aludel.Providers
  alias Aludel.RedTeam

  @generation_defaults %{
    "provider_id" => "",
    "categories" => ["prompt_injection"],
    "cases_per_category" => "2",
    "target_context" => "",
    "max_requests" => "6",
    "max_output_tokens" => "1200",
    "max_total_tokens" => "20000",
    "max_cost_usd" => "5.00",
    "request_timeout_ms" => "30000"
  }
  @import_defaults %{
    "approved_case_ids" => [],
    "variable" => "input",
    "judge_provider_id" => "",
    "judge_threshold" => "80"
  }
  @generation_field_errors %{
    "cases_per_category" => "Cases per category must be an integer between 1 and 5",
    "max_requests" => "Request limit must be an integer between 1 and 6",
    "max_output_tokens" => "Output-token limit must be an integer between 100 and 4,000",
    "max_total_tokens" => "Total-token limit must be an integer between 100 and 100,000",
    "max_cost_usd" => "Cost limit must be greater than 0 and no more than 100 USD",
    "request_timeout_ms" =>
      "Request timeout must be an integer between 100 and 120,000 milliseconds"
  }

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_params(%{"id" => id}, _uri, socket) do
    dataset = Datasets.get_dataset!(id)
    providers = Providers.list_providers()
    provider_id = default_provider_id(providers)

    {:noreply,
     socket
     |> assign(:page_title, "Generate red-team cases")
     |> assign(:dataset, dataset)
     |> assign(:providers, providers)
     |> assign(:categories, RedTeam.categories())
     |> assign(:generating, false)
     |> assign(:generation, nil)
     |> assign(:generation_errors, [])
     |> assign(:import_errors, [])
     |> assign(:import_result, nil)
     |> assign_generation_form(Map.put(@generation_defaults, "provider_id", provider_id))
     |> assign_import_form(@import_defaults)}
  end

  @impl Phoenix.LiveView
  def handle_event("validate_generation", %{"generation" => params}, socket) do
    {:noreply,
     socket
     |> assign_generation_form(params)
     |> assign(:generation_errors, [])}
  end

  def handle_event(
        "generate",
        %{"generation" => params},
        %{assigns: %{generating: false}} = socket
      ) do
    case generation_options(params, socket.assigns.categories, socket.assigns.providers) do
      {:ok, provider_id, options} ->
        socket =
          start_async(socket, :generate_red_team_cases, fn ->
            RedTeam.generate(provider_id, options)
          end)

        {:noreply,
         socket
         |> assign_generation_form(params)
         |> assign(:generating, true)
         |> assign(:generation, nil)
         |> assign(:generation_errors, [])
         |> assign(:import_errors, [])
         |> assign(:import_result, nil)
         |> assign_import_form(@import_defaults)}

      {:error, message} ->
        {:noreply,
         socket
         |> assign_generation_form(params)
         |> assign(:generation_errors, [message])}
    end
  end

  def handle_event("generate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("validate_import", %{"import" => params}, socket) do
    {:noreply,
     socket
     |> assign_import_form(params)
     |> assign(:import_errors, [])
     |> assign(:import_result, nil)}
  end

  def handle_event("import", %{"import" => params}, socket) do
    with {:ok, generation} <- current_generation(socket.assigns.generation),
         {:ok, options} <- import_options(params, generation, socket.assigns.providers) do
      import_generated(socket, params, generation, options)
    else
      {:error, message} ->
        {:noreply,
         socket
         |> assign_import_form(params)
         |> assign(:import_errors, [message])
         |> assign(:import_result, nil)}
    end
  end

  @impl Phoenix.LiveView
  def handle_async(:generate_red_team_cases, {:ok, {:ok, generation}}, socket) do
    import_params =
      Map.put(@import_defaults, "judge_provider_id", generation.provider.id)

    {:noreply,
     socket
     |> assign(:generating, false)
     |> assign(:generation, generation)
     |> assign(:generation_errors, [])
     |> assign(:import_errors, [])
     |> assign(:import_result, nil)
     |> assign_import_form(import_params)}
  end

  def handle_async(:generate_red_team_cases, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:generating, false)
     |> assign(:generation_errors, [generation_error(reason)])}
  end

  def handle_async(:generate_red_team_cases, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:generating, false)
     |> assign(:generation_errors, ["Generation could not be completed"])}
  end

  defp generation_options(params, categories, providers) do
    with {:ok, provider_id} <- configured_provider(params["provider_id"], providers),
         {:ok, selected_categories} <- selected_categories(params["categories"], categories),
         {:ok, cases_per_category} <- bounded_integer(params, "cases_per_category", 1, 5),
         {:ok, max_requests} <- bounded_integer(params, "max_requests", 1, 6),
         {:ok, max_output_tokens} <- bounded_integer(params, "max_output_tokens", 100, 4_000),
         {:ok, max_total_tokens} <- bounded_integer(params, "max_total_tokens", 100, 100_000),
         :ok <- validate_total_tokens(max_total_tokens, max_output_tokens),
         {:ok, max_cost_usd} <- bounded_number(params, "max_cost_usd", 0, 100),
         {:ok, request_timeout_ms} <-
           bounded_integer(params, "request_timeout_ms", 100, 120_000),
         {:ok, target_context} <- target_context(params["target_context"]) do
      {:ok, provider_id,
       [
         categories: selected_categories,
         cases_per_category: cases_per_category,
         target_context: target_context,
         max_requests: max_requests,
         max_output_tokens: max_output_tokens,
         max_total_tokens: max_total_tokens,
         max_cost_usd: max_cost_usd,
         request_timeout_ms: request_timeout_ms
       ]}
    else
      {:error, field, range} -> {:error, generation_field_error(field, range)}
      {:error, message} -> {:error, message}
    end
  end

  defp import_options(params, generation, providers) do
    with {:ok, approved_ids} <- approved_case_ids(params["approved_case_ids"], generation),
         :ok <- validate_variable(params["variable"]),
         {:ok, provider_id} <- configured_provider(params["judge_provider_id"], providers),
         {:ok, threshold} <- judge_threshold(params["judge_threshold"]) do
      {:ok,
       [
         approved_case_ids: approved_ids,
         variable: params["variable"],
         judge_provider_id: provider_id,
         judge_threshold: threshold
       ]}
    end
  end

  defp import_generated(socket, params, generation, options) do
    case RedTeam.import_generated(socket.assigns.dataset, generation, options) do
      {:ok, result} ->
        created_count = length(result.created)
        skipped_count = length(result.skipped)

        {:noreply,
         socket
         |> assign_import_form(params)
         |> assign(:import_errors, [])
         |> assign(:import_result, %{created: created_count, skipped: skipped_count})
         |> put_flash(:info, import_message(created_count, skipped_count))}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign_import_form(params)
         |> assign(:import_errors, [import_error(reason)])
         |> assign(:import_result, nil)}
    end
  end

  defp current_generation(nil) do
    {:error, "Generate cases before importing"}
  end

  defp current_generation(generation) do
    {:ok, generation}
  end

  defp configured_provider(provider_id, providers) do
    if is_binary(provider_id) and Enum.any?(providers, &(&1.id == provider_id)) do
      {:ok, provider_id}
    else
      {:error, "Choose a configured provider"}
    end
  end

  defp default_provider_id([provider | _providers]) do
    provider.id
  end

  defp default_provider_id([]) do
    ""
  end

  defp selected_categories(values, categories) do
    values = List.wrap(values)
    known = Map.new(categories, &{Atom.to_string(&1), &1})

    cond do
      values == [] ->
        {:error, "Select at least one category"}

      Enum.uniq(values) != values ->
        {:error, "Select each category only once"}

      true ->
        map_selected_categories(values, known)
    end
  end

  defp map_selected_categories(values, known) do
    selected = Enum.map(values, &Map.get(known, &1))

    if Enum.any?(selected, &is_nil/1) do
      {:error, "Choose only supported categories"}
    else
      {:ok, selected}
    end
  end

  defp approved_case_ids(values, generation) do
    values = List.wrap(values)
    known_ids = MapSet.new(generation.cases, & &1.id)

    cond do
      values == [] ->
        {:error, "Approve at least one generated case"}

      Enum.uniq(values) != values ->
        {:error, "Approve each generated case only once"}

      Enum.any?(values, &(not MapSet.member?(known_ids, &1))) ->
        {:error, "Choose only cases from the current review receipt"}

      true ->
        {:ok, values}
    end
  end

  defp bounded_integer(params, field, min, max) do
    with value when is_binary(value) <- Map.get(params, field),
         {parsed, ""} <- Integer.parse(value),
         true <- parsed >= min and parsed <= max do
      {:ok, parsed}
    else
      _invalid -> {:error, field, min..max}
    end
  end

  defp bounded_number(params, field, exclusive_min, max) do
    with value when is_binary(value) <- Map.get(params, field),
         {parsed, ""} <- Float.parse(value),
         true <- parsed > exclusive_min and parsed <= max do
      {:ok, parsed}
    else
      _invalid -> {:error, field, exclusive_min..max}
    end
  end

  defp judge_threshold(value) when is_binary(value) do
    case Float.parse(value) do
      {parsed, ""} when parsed >= 0 and parsed <= 100 -> {:ok, parsed}
      _invalid -> invalid_judge_threshold()
    end
  end

  defp judge_threshold(_value) do
    invalid_judge_threshold()
  end

  defp invalid_judge_threshold do
    {:error, "Judge threshold must be a number between 0 and 100"}
  end

  defp validate_total_tokens(max_total_tokens, max_output_tokens)
       when max_total_tokens >= max_output_tokens do
    :ok
  end

  defp validate_total_tokens(_max_total_tokens, _max_output_tokens) do
    {:error, "Total-token limit must be at least the per-request output-token limit"}
  end

  defp target_context(value) when is_binary(value) do
    if String.valid?(value) and String.length(value) <= 10_000 do
      {:ok, value}
    else
      {:error, "Target context must be at most 10,000 characters"}
    end
  end

  defp target_context(_value) do
    {:error, "Target context must be at most 10,000 characters"}
  end

  defp validate_variable(value) when is_binary(value) do
    if String.valid?(value) and byte_size(value) <= 200 and
         Regex.match?(~r/\A[a-zA-Z_][a-zA-Z0-9_.-]*\z/u, value) do
      :ok
    else
      {:error,
       "Variable must start with a letter or underscore and use only letters, numbers, dots, dashes, or underscores"}
    end
  end

  defp validate_variable(_value) do
    {:error, "Enter a valid prompt variable"}
  end

  defp generation_field_error(field, _range) do
    Map.fetch!(@generation_field_errors, field)
  end

  defp generation_error(:provider_not_found) do
    "The selected provider no longer exists"
  end

  defp generation_error(_reason) do
    "Generation options could not be accepted"
  end

  defp import_error(:invalid_generation) do
    "The current review receipt failed integrity validation"
  end

  defp import_error(:invalid_approved_case_ids) do
    "Approve at least one generated case"
  end

  defp import_error(:invalid_variable) do
    "Enter a valid prompt variable"
  end

  defp import_error(:invalid_judge_provider_id) do
    "Choose a configured judge provider"
  end

  defp import_error(:invalid_judge_threshold) do
    "Judge threshold must be a number between 0 and 100"
  end

  defp import_error({:deduplication_conflict, _key}) do
    "An existing entry conflicts with the approved generated case"
  end

  defp import_error(_reason) do
    "Approved cases could not be imported"
  end

  defp assign_generation_form(socket, params) do
    socket
    |> assign(:selected_categories, params |> Map.get("categories", []) |> List.wrap())
    |> assign(:generation_form, to_form(params, as: :generation))
  end

  defp assign_import_form(socket, params) do
    socket
    |> assign(:approved_case_ids, params |> Map.get("approved_case_ids", []) |> List.wrap())
    |> assign(:import_form, to_form(params, as: :import))
  end

  defp import_message(created, 0) do
    "#{created} #{case_label(created)} imported"
  end

  defp import_message(0, skipped) do
    "#{skipped} #{case_label(skipped)} already present"
  end

  defp import_message(created, skipped) do
    "#{created} #{case_label(created)} imported; #{skipped} already present"
  end

  defp case_label(1) do
    "case"
  end

  defp case_label(_count) do
    "cases"
  end

  defp category_label(category) do
    category
    |> Atom.to_string()
    |> String.replace("_", " ")
  end

  defp format_cost(cost) when is_number(cost) do
    :erlang.float_to_binary(cost / 1, decimals: 4)
  end
end
