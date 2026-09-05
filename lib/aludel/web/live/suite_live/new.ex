defmodule Aludel.Web.SuiteLive.New do
  @moduledoc """
  LiveView for creating a new evaluation suite.
  """

  use Aludel.Web, :live_view

  alias Aludel.Evals
  alias Aludel.Evals.AssertionParser
  alias Aludel.Evals.DocumentIngestion
  alias Aludel.Evals.JudgeCatalog
  alias Aludel.Evals.Suite
  alias Aludel.Projects
  alias Aludel.Prompts
  alias Aludel.Providers

  @document_upload_names Enum.map(0..49, &:"test_case_documents_#{&1}")
  @document_upload_accept ~w(.pdf .png .jpg .jpeg .csv .json .txt)
  @document_upload_max_entries 5
  @document_upload_max_file_size 10_000_000

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    socket = apply_action(socket, socket.assigns.live_action, params)
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"suite" => suite_params}, socket) do
    selected_prompt = find_selected_prompt(socket.assigns.prompts, suite_params["prompt_id"])

    changeset =
      socket.assigns.suite
      |> Evals.change_suite(Map.drop(suite_params, ["test_cases"]))
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:suite, Ecto.Changeset.apply_changes(changeset))
     |> assign(:form, to_form(changeset))
     |> assign(:selected_prompt, selected_prompt)
     |> assign(
       :test_case_form_params,
       merge_test_case_form_params(suite_params, socket.assigns.test_cases, selected_prompt)
     )
     |> assign(
       :test_cases,
       merge_test_cases_from_params(suite_params, socket.assigns.test_cases, selected_prompt)
     )}
  end

  @impl Phoenix.LiveView
  def handle_event("add_test_case", _params, socket) do
    # Extract variables from selected prompt
    variable_values =
      case socket.assigns.selected_prompt do
        %{versions: [%{template: template} | _]} ->
          variables = extract_variables(template)
          Map.new(variables, fn var -> {var, ""} end)

        _ ->
          %{}
      end

    case next_document_upload_name(socket) do
      nil ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "You can add up to #{length(@document_upload_names)} test cases with uploads"
         )}

      upload_name ->
        new_test_case = %{
          id: generate_id(),
          upload_name: upload_name,
          assertions: [],
          variable_values: variable_values
        }

        test_cases = socket.assigns.test_cases ++ [new_test_case]

        {:noreply,
         socket
         |> allow_document_upload(upload_name)
         |> assign(:test_cases, test_cases)
         |> put_test_case_form_params(new_test_case)}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("remove_test_case", %{"id" => id}, socket) do
    removed_test_case = Enum.find(socket.assigns.test_cases, fn tc -> tc.id == id end)
    test_cases = Enum.reject(socket.assigns.test_cases, fn tc -> tc.id == id end)

    {:noreply,
     socket
     |> disallow_document_upload(removed_test_case)
     |> assign(:test_cases, test_cases)
     |> assign(:test_case_form_params, Map.delete(socket.assigns.test_case_form_params, id))
     |> assign(:assertion_edit_mode, Map.delete(socket.assigns.assertion_edit_mode, id))}
  end

  @impl Phoenix.LiveView
  def handle_event("toggle_assertion_mode", %{"id" => id}, socket) do
    current_mode = Map.get(socket.assigns.assertion_edit_mode, id, :visual)
    new_mode = if current_mode == :visual, do: :json, else: :visual
    new_modes = Map.put(socket.assigns.assertion_edit_mode, id, new_mode)
    {:noreply, assign(socket, :assertion_edit_mode, new_modes)}
  end

  @impl Phoenix.LiveView
  def handle_event("add_assertion", %{"id" => id}, socket) do
    test_cases =
      Enum.map(socket.assigns.test_cases, fn tc ->
        if tc.id == id do
          new_assertion = %{"type" => "contains", "value" => ""}
          %{tc | assertions: (tc[:assertions] || []) ++ [new_assertion]}
        else
          tc
        end
      end)

    {:noreply, sync_test_case_form_params(socket, test_cases, id)}
  end

  @impl Phoenix.LiveView
  def handle_event("remove_assertion", %{"id" => id, "index" => index_str}, socket) do
    index = String.to_integer(index_str)

    test_cases =
      Enum.map(socket.assigns.test_cases, fn tc ->
        if tc.id == id do
          assertions = tc[:assertions] || []
          %{tc | assertions: List.delete_at(assertions, index)}
        else
          tc
        end
      end)

    {:noreply, sync_test_case_form_params(socket, test_cases, id)}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"suite" => suite_params}, socket) do
    save_suite(socket, socket.assigns.live_action, suite_params)
  end

  defp apply_action(socket, :new, params) do
    project_id = Map.get(params, "project_id")
    initial_data = if project_id, do: %{"project_id" => project_id}, else: %{}
    suite = %Suite{project_id: project_id}
    changeset = Evals.change_suite(suite, initial_data)
    prompts = Prompts.list_prompts_with_versions()
    projects = Projects.list_projects(type: :suite)
    providers = Providers.list_providers()

    socket
    |> assign(:page_title, "New Suite")
    |> assign(:suite, suite)
    |> assign(:form, to_form(changeset))
    |> assign(:prompts, prompts)
    |> assign(:projects, projects)
    |> assign(:providers, providers)
    |> assign(:judge_templates, JudgeCatalog.all())
    |> assign(:test_cases, [])
    |> assign(:selected_prompt, nil)
    |> assign(:assertion_edit_mode, %{})
    |> assign(:test_case_form_params, %{})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    suite = Evals.get_suite_with_test_cases_and_prompt!(id)
    changeset = Evals.change_suite(suite)
    prompts = Prompts.list_prompts_with_versions()
    projects = Projects.list_projects(type: :suite)
    providers = Providers.list_providers()

    # Get the selected prompt if suite has one
    selected_prompt =
      if suite.prompt_id do
        Enum.find(prompts, fn p -> p.id == suite.prompt_id end)
      else
        nil
      end

    # Convert existing test cases to the format expected by the form
    test_cases =
      Enum.map(suite.test_cases, fn tc ->
        %{
          id: tc.id,
          variable_values: tc.variable_values,
          assertions: tc.assertions
        }
      end)

    {test_cases, socket} = assign_document_uploads(socket, test_cases)

    socket
    |> assign(:page_title, "Edit Suite")
    |> assign(:suite, suite)
    |> assign(:form, to_form(changeset))
    |> assign(:prompts, prompts)
    |> assign(:projects, projects)
    |> assign(:providers, providers)
    |> assign(:judge_templates, JudgeCatalog.all())
    |> assign(:test_cases, test_cases)
    |> assign(:selected_prompt, selected_prompt)
    |> assign(:assertion_edit_mode, %{})
    |> assign(:test_case_form_params, build_test_case_form_params_map(test_cases))
  end

  defp save_suite(socket, :new, suite_params) do
    case validate_test_cases(suite_params) do
      :ok ->
        case create_suite_with_test_cases(socket, suite_params) do
          {:ok, suite, upload_results} ->
            {:noreply,
             socket
             |> put_create_suite_flash(upload_results)
             |> push_navigate(to: aludel_path("suites/#{suite.id}"))}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply,
             socket
             |> assign(:form, to_form(changeset))
             |> assign(
               :test_cases,
               merge_test_cases_from_params(
                 suite_params,
                 socket.assigns.test_cases,
                 socket.assigns.selected_prompt
               )
             )}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, suite_save_error_message(reason))}
        end

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  defp save_suite(socket, :edit, suite_params) do
    case validate_test_cases(suite_params) do
      :ok ->
        case update_suite_with_test_cases(socket, socket.assigns.suite, suite_params) do
          {:ok, suite, upload_results} ->
            {:noreply,
             socket
             |> put_update_suite_flash(upload_results)
             |> push_navigate(to: aludel_path("suites/#{suite.id}"))}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply,
             socket
             |> assign(:form, to_form(changeset))
             |> assign(
               :test_cases,
               merge_test_cases_from_params(
                 suite_params,
                 socket.assigns.test_cases,
                 socket.assigns.selected_prompt
               )
             )}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, suite_save_error_message(reason))}
        end

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  defp validate_test_cases(params) do
    test_cases = params["test_cases"] || %{}

    test_cases
    |> Enum.reduce_while(:ok, fn {_id, test_case_params}, _acc ->
      case parse_test_case_assertions(test_case_params) do
        {:ok, _assertions} -> {:cont, :ok}
        {:error, _message} = error -> {:halt, error}
      end
    end)
  end

  defp parse_test_case_assertions(%{"assertions_json" => assertions_json}) do
    AssertionParser.parse(:json, %{"assertions_json" => assertions_json})
  end

  defp parse_test_case_assertions(test_case_params) do
    AssertionParser.parse(:visual, test_case_params)
  end

  defp create_suite_with_test_cases(socket, params) do
    test_cases_params = extract_test_cases(params, socket.assigns.test_cases, socket)
    repo = Aludel.Repo.get()

    repo.transaction(fn ->
      with {:ok, suite} <- Evals.create_suite(Map.drop(params, ["test_cases"])),
           {:ok, upload_results} <- create_test_cases_for_suite(socket, suite, test_cases_params) do
        {suite, upload_results}
      else
        {:error, reason} -> repo.rollback(reason)
      end
    end)
    |> suite_transaction_result()
  end

  defp extract_test_cases(params, current_test_cases, socket) do
    test_cases = params["test_cases"] || %{}
    current_test_cases_by_id = Map.new(current_test_cases, &{&1.id, &1})

    test_cases
    |> Enum.map(fn {id, test_case_params} ->
      variable_values = Map.get(test_case_params, "variable_values", %{})

      assertions =
        case parse_test_case_assertions(test_case_params) do
          {:ok, assertions} -> assertions
          {:error, _message} -> []
        end

      upload_name =
        current_test_cases_by_id
        |> Map.get(id, %{})
        |> Map.get(:upload_name)

      %{
        upload_name: upload_name,
        has_uploads: upload_name_has_entries?(socket, upload_name),
        variable_values: variable_values,
        assertions: assertions
      }
    end)
    |> Enum.reject(&empty_test_case?/1)
  end

  defp create_test_cases_for_suite(socket, suite, test_cases_params) do
    test_cases_params
    |> Enum.reduce_while({:ok, []}, fn tc_params, {:ok, created_test_cases} ->
      attrs =
        tc_params
        |> Map.take([:variable_values, :assertions])
        |> Map.put(:suite_id, suite.id)

      case Evals.create_test_case(attrs) do
        {:ok, test_case} ->
          {:cont, {:ok, [{tc_params, test_case} | created_test_cases]}}

        {:error, changeset} ->
          {:halt, {:error, {:test_case, changeset}}}
      end
    end)
    |> case do
      {:ok, created_test_cases} ->
        upload_results =
          created_test_cases
          |> Enum.reverse()
          |> Enum.flat_map(fn {tc_params, test_case} ->
            handle_test_case_uploads(socket, tc_params, test_case)
          end)

        {:ok, upload_results}

      {:error, _reason} = error ->
        error
    end
  end

  defp update_suite_with_test_cases(socket, suite, params) do
    test_cases_params = extract_test_cases(params, socket.assigns.test_cases, socket)
    repo = Aludel.Repo.get()

    repo.transaction(fn ->
      with {:ok, suite} <- Evals.update_suite(suite, Map.drop(params, ["test_cases"])),
           :ok <- delete_test_cases(suite.test_cases),
           {:ok, upload_results} <- create_test_cases_for_suite(socket, suite, test_cases_params) do
        {suite, upload_results}
      else
        {:error, reason} -> repo.rollback(reason)
      end
    end)
    |> suite_transaction_result()
  end

  defp suite_transaction_result({:ok, {suite, upload_results}}), do: {:ok, suite, upload_results}
  defp suite_transaction_result({:error, reason}), do: {:error, reason}

  defp delete_test_cases(test_cases) do
    Enum.reduce_while(test_cases, :ok, fn test_case, :ok ->
      case Evals.delete_test_case(test_case) do
        {:ok, _test_case} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, {:test_case, changeset}}}
      end
    end)
  end

  defp merge_test_case_assertions(test_case_params) do
    case preview_test_case_assertions(test_case_params) do
      {:ok, assertions} -> assertions
      {:error, _message} -> []
    end
  end

  defp preview_test_case_assertions(%{"assertions_json" => assertions_json}) do
    AssertionParser.parse(:json, %{"assertions_json" => assertions_json})
  end

  defp preview_test_case_assertions(test_case_params) do
    AssertionParser.preview_visual(test_case_params)
  end

  defp extract_variables(template) do
    ~r/\{\{([^}]+)\}\}/
    |> Regex.scan(template)
    |> Enum.map(fn [_, var] -> String.trim(var) end)
    |> Enum.uniq()
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp find_selected_prompt(_prompts, prompt_id) when prompt_id in [nil, ""], do: nil
  defp find_selected_prompt(prompts, prompt_id), do: Enum.find(prompts, &(&1.id == prompt_id))

  defp sync_test_case_variables(test_cases, selected_prompt) do
    variables = prompt_variables(selected_prompt)

    Enum.map(test_cases, fn tc ->
      variable_values =
        variables
        |> Enum.map(fn var -> {var, Map.get(tc[:variable_values] || %{}, var, "")} end)
        |> Map.new()

      Map.put(tc, :variable_values, variable_values)
    end)
  end

  defp merge_test_cases_from_params(
         %{"test_cases" => test_cases_params},
         current_test_cases,
         selected_prompt
       )
       when is_map(test_cases_params) and map_size(test_cases_params) > 0 do
    variables = prompt_variables(selected_prompt)

    Enum.map(test_cases_params, fn {id, test_case_params} ->
      variable_values =
        variables
        |> Enum.map(fn var ->
          {var, get_in(test_case_params, ["variable_values", var]) || ""}
        end)
        |> Map.new()

      %{
        id: id,
        upload_name: current_test_case_upload_name(current_test_cases, id),
        variable_values: variable_values,
        assertions: merge_test_case_assertions(test_case_params)
      }
    end)
  end

  defp merge_test_cases_from_params(
         %{"test_cases" => _test_cases_params},
         current_test_cases,
         selected_prompt
       ) do
    sync_test_case_variables(current_test_cases, selected_prompt)
  end

  defp merge_test_cases_from_params(_suite_params, current_test_cases, selected_prompt) do
    sync_test_case_variables(current_test_cases, selected_prompt)
  end

  defp merge_test_case_form_params(
         %{"test_cases" => test_cases_params},
         _current_test_cases,
         selected_prompt
       )
       when is_map(test_cases_params) and map_size(test_cases_params) > 0 do
    variables = prompt_variables(selected_prompt)

    Map.new(test_cases_params, fn {id, test_case_params} ->
      variable_values =
        variables
        |> Enum.map(fn var ->
          {var, get_in(test_case_params, ["variable_values", var]) || ""}
        end)
        |> Map.new()

      assertion_params =
        test_case_params
        |> Map.get("assertions", %{})
        |> normalize_form_assertion_params()

      assertions = merge_test_case_assertions(test_case_params)

      form_params =
        %{"variable_values" => variable_values}
        |> Map.merge(AssertionParser.build_form_params(assertions))
        |> Map.put("assertions", assertion_params)
        |> maybe_put_assertions_json_param(test_case_params)

      {id, form_params}
    end)
  end

  defp merge_test_case_form_params(
         %{"test_cases" => _test_cases_params},
         current_test_cases,
         selected_prompt
       ) do
    current_test_cases
    |> sync_test_case_variables(selected_prompt)
    |> build_test_case_form_params_map()
  end

  defp merge_test_case_form_params(_suite_params, current_test_cases, selected_prompt) do
    current_test_cases
    |> sync_test_case_variables(selected_prompt)
    |> build_test_case_form_params_map()
  end

  defp build_test_case_form_params_map(test_cases) do
    Map.new(test_cases, fn test_case ->
      {test_case.id, build_test_case_form_params(test_case)}
    end)
  end

  defp build_test_case_form_params(test_case) do
    %{
      "variable_values" => test_case[:variable_values] || %{}
    }
    |> Map.merge(AssertionParser.build_form_params(test_case[:assertions] || []))
  end

  defp put_test_case_form_params(socket, test_case) do
    assign(
      socket,
      :test_case_form_params,
      Map.put(
        socket.assigns.test_case_form_params,
        test_case.id,
        build_test_case_form_params(test_case)
      )
    )
  end

  defp sync_test_case_form_params(socket, test_cases, id) do
    updated_test_case = Enum.find(test_cases, &(&1.id == id))

    socket
    |> assign(:test_cases, test_cases)
    |> put_test_case_form_params(updated_test_case)
  end

  defp maybe_put_assertions_json_param(form_params, %{"assertions_json" => assertions_json}) do
    Map.put(form_params, "assertions_json", assertions_json || "")
  end

  defp maybe_put_assertions_json_param(form_params, _test_case_params), do: form_params

  defp normalize_form_assertion_params(params) when is_map(params), do: params
  defp normalize_form_assertion_params(params) when is_list(params), do: Map.new(params)
  defp normalize_form_assertion_params(_params), do: %{}

  defp current_assertion_type(test_case_id, idx, form_params, assertion) do
    assertion_form_value(test_case_id, idx, "type", form_params) || assertion["type"] ||
      "contains"
  end

  defp assertion_text_value(test_case_id, idx, field_name, assertion_key, form_params, assertion) do
    case assertion_form_value(test_case_id, idx, field_name, form_params) ||
           assertion[assertion_key] do
      nil -> ""
      value -> display_value(value)
    end
  end

  defp assertion_expected_json_value_for_json_field(test_case_id, idx, form_params, assertion) do
    case assertion_form_value(test_case_id, idx, "expected_json_value", form_params) do
      nil ->
        Jason.encode!(Map.get(assertion, "expected", ""))

      value ->
        value
    end
  end

  defp assertion_expected_json_value(test_case_id, idx, form_params, assertion) do
    case assertion_form_value(test_case_id, idx, "expected_json", form_params) do
      nil ->
        if is_map(assertion["expected"]) or is_list(assertion["expected"]) do
          Jason.encode!(assertion["expected"], pretty: true)
        else
          ""
        end

      value ->
        value
    end
  end

  defp assertion_threshold_value(test_case_id, idx, form_params, assertion) do
    case assertion_form_value(test_case_id, idx, "threshold", form_params) do
      nil ->
        if is_number(assertion["threshold"]), do: to_string(assertion["threshold"]), else: ""

      value ->
        value
    end
  end

  defp assertion_rubric_source_value(test_case_id, idx, form_params, assertion) do
    case assertion_form_value(test_case_id, idx, "rubric_source", form_params) do
      nil -> if is_binary(assertion["rubric"]), do: "custom", else: "template"
      value -> value
    end
  end

  defp assertion_evidence_json_value(
         test_case_id,
         idx,
         field_name,
         form_params,
         assertion
       ) do
    case assertion_form_value(test_case_id, idx, "#{field_name}_json_value", form_params) do
      nil -> Jason.encode!(Map.get(assertion, field_name))
      value -> value
    end
  end

  defp judge_provider_options(providers, selected_id) do
    options = Enum.map(providers, &{&1.name, &1.id})

    if selected_id == "" or Enum.any?(providers, &(&1.id == selected_id)) do
      options
    else
      [{"Unavailable provider (#{selected_id})", selected_id} | options]
    end
  end

  defp assertion_form_value(test_case_id, idx, field_name, form_params) do
    form_params
    |> Map.get(test_case_id, %{})
    |> Map.get("assertions", %{})
    |> normalize_form_assertion_params()
    |> Map.get("assertion_#{field_name}_#{idx}")
  end

  defp test_case_assertions_json_value(test_case, form_params) do
    case Map.get(form_params, test_case.id, %{}) do
      %{"assertions_json" => assertions_json} ->
        assertions_json

      _other ->
        if test_case[:assertions], do: Jason.encode!(test_case.assertions, pretty: true), else: ""
    end
  end

  defp display_value(nil), do: "null"
  defp display_value(value) when is_binary(value), do: value

  defp display_value(value) when is_integer(value) or is_float(value) or is_boolean(value),
    do: inspect(value)

  defp display_value(value) when is_map(value) or is_list(value), do: Jason.encode!(value)
  defp display_value(value), do: to_string(value)

  defp assign_document_uploads(socket, test_cases) do
    {test_cases, {socket, _assigned_test_cases}} =
      Enum.map_reduce(test_cases, {socket, []}, fn test_case, {socket, assigned_test_cases} ->
        case next_document_upload_name(socket, assigned_test_cases) do
          nil ->
            {test_case, {socket, assigned_test_cases}}

          upload_name ->
            test_case = Map.put(test_case, :upload_name, upload_name)

            {test_case,
             {allow_document_upload(socket, upload_name), [test_case | assigned_test_cases]}}
        end
      end)

    {test_cases, socket}
  end

  defp next_document_upload_name(socket) do
    next_document_upload_name(socket, Map.get(socket.assigns, :test_cases, []))
  end

  defp next_document_upload_name(_socket, test_cases) do
    used_upload_names =
      test_cases
      |> Enum.map(&Map.get(&1, :upload_name))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    Enum.find(@document_upload_names, &(not MapSet.member?(used_upload_names, &1)))
  end

  defp allow_document_upload(socket, upload_name) do
    allow_upload(socket, upload_name,
      accept: @document_upload_accept,
      max_entries: @document_upload_max_entries,
      max_file_size: @document_upload_max_file_size
    )
  end

  defp disallow_document_upload(socket, nil), do: socket

  defp disallow_document_upload(socket, test_case) do
    case Map.get(test_case, :upload_name) do
      nil ->
        socket

      upload_name ->
        socket
        |> cancel_document_upload_entries(upload_name)
        |> disallow_upload(upload_name)
    end
  end

  defp cancel_document_upload_entries(socket, upload_name) do
    case get_in(socket.assigns, [:uploads, upload_name]) do
      nil ->
        socket

      upload ->
        Enum.reduce(upload.entries, socket, fn entry, socket ->
          cancel_upload(socket, upload_name, entry.ref)
        end)
    end
  end

  defp current_test_case_upload_name(test_cases, id) do
    test_cases
    |> Enum.find(%{}, &(&1.id == id))
    |> Map.get(:upload_name)
  end

  defp upload_name_has_entries?(_socket, nil), do: false
  defp upload_name_has_entries?(nil, _upload_name), do: false

  defp upload_name_has_entries?(socket, upload_name) do
    socket.assigns
    |> Map.get(:uploads, %{})
    |> Map.get(upload_name)
    |> case do
      nil -> false
      upload -> upload.entries != []
    end
  end

  defp empty_test_case?(test_case) do
    test_case.variable_values == %{} and test_case.assertions == [] and not test_case.has_uploads
  end

  defp handle_test_case_uploads(_socket, %{upload_name: nil}, _test_case), do: []

  defp handle_test_case_uploads(socket, %{upload_name: upload_name}, test_case) do
    consume_uploaded_entries(socket, upload_name, fn %{path: path}, entry ->
      {:ok, DocumentIngestion.ingest(path, entry, test_case.id)}
    end)
  end

  defp successful_upload?({:success, _filename}), do: true
  defp successful_upload?(_result), do: false

  defp put_create_suite_flash(socket, upload_results) do
    put_suite_upload_flash(socket, :created, upload_results)
  end

  defp put_update_suite_flash(socket, upload_results) do
    put_suite_upload_flash(socket, :updated, upload_results)
  end

  defp put_suite_upload_flash(socket, action, upload_results) do
    case Enum.split_with(upload_results, &successful_upload?/1) do
      {[], []} ->
        put_flash(socket, :info, "Suite #{action} successfully")

      {[], failed_uploads} ->
        failed_files = failed_uploads |> failed_uploads_message()
        put_flash(socket, :error, "Suite #{action} but document uploads failed: #{failed_files}")

      {successful_uploads, []} ->
        put_flash(socket, :info, "Suite #{action} with #{length(successful_uploads)} document(s)")

      {successful_uploads, failed_uploads} ->
        failed_count = length(failed_uploads)
        success_count = length(successful_uploads)

        put_flash(
          socket,
          :warning,
          "Suite #{action} with #{success_count} document(s), but #{failed_count} failed validation"
        )
    end
  end

  defp failed_uploads_message(failed_uploads) do
    Enum.map_join(failed_uploads, ", ", fn {:failed, name, reason} ->
      "#{name} (#{reason})"
    end)
  end

  defp suite_save_error_message({:test_case, %Ecto.Changeset{} = changeset}) do
    "Could not save test case: #{format_changeset_errors(changeset)}"
  end

  defp suite_save_error_message(reason), do: "Could not save suite: #{inspect(reason)}"

  defp format_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join(", ", fn {field, messages} ->
      "#{field} #{Enum.join(messages, ", ")}"
    end)
  end

  defp prompt_variables(%{versions: [%{template: template} | _]}), do: extract_variables(template)
  defp prompt_variables(_selected_prompt), do: []
end
