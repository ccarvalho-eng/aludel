defmodule Aludel.Web.SuiteLive.Show do
  @moduledoc """
  LiveView for displaying a single evaluation suite.

  Shows suite details, test cases, and allows running the suite
  against a specific prompt version and provider.
  """

  use Aludel.Web, :live_view

  alias Aludel.Datasets
  alias Aludel.Evals
  alias Aludel.Evals.AssertionParser
  alias Aludel.Evals.DocumentIngestion
  alias Aludel.Evals.JudgeCatalog
  alias Aludel.Evals.TestCaseEditor
  alias Aludel.Evals.TestCaseImporter
  alias Aludel.Executor
  alias Aludel.Projects
  alias Aludel.Prompts
  alias Aludel.Providers
  alias Decimal

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:show_test_case_import, false)
      |> assign(:test_case_import_preview, nil)
      |> assign(:test_case_import_form, to_form(%{}, as: :test_case_import))
      |> allow_upload(:test_case_import,
        accept: ~w(.csv .json),
        max_entries: 1,
        max_file_size: 2_000_000
      )

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_params(%{"id" => id}, _uri, socket) do
    suite = Evals.get_suite_with_test_cases_and_prompt!(id)
    prompt = Prompts.get_prompt_with_versions!(suite.prompt_id)
    providers = Providers.list_providers()
    all_prompts = Prompts.list_prompts()
    projects = Projects.list_projects(type: :suite)
    datasets = Datasets.list_datasets()

    # Load existing suite runs
    suite_runs = Evals.list_suite_runs_for_suite_with_associations(id)

    # Set default selections to first version and first provider
    default_version_id = List.first(prompt.versions) |> then(&if &1, do: &1.id, else: nil)
    default_provider_id = List.first(providers) |> then(&if &1, do: &1.id, else: nil)

    socket =
      socket
      |> assign(:page_title, suite.name)
      |> assign(:suite, suite)
      |> assign(:prompt, prompt)
      |> assign(:selected_prompt_version, selected_prompt_version(prompt, default_version_id))
      |> assign(:all_prompts, all_prompts)
      |> assign(:projects, projects)
      |> assign(:datasets, datasets)
      |> assign(:dataset_import_form, to_form(%{"dataset_id" => ""}, as: :dataset_import))
      |> assign(:dataset_import_status, nil)
      |> assign(:providers, providers)
      |> assign(:judge_templates, JudgeCatalog.all())
      |> assign(:execution_mode_label, Executor.execution_mode_label())
      |> assign(:suite_runs, suite_runs)
      |> assign(:running, false)
      |> assign(:run_task_monitor_ref, nil)
      |> assign(:selected_version_id, default_version_id)
      |> assign(:selected_provider_id, default_provider_id)
      |> assign(:run_suite_form, build_run_suite_form(default_version_id, default_provider_id))
      |> assign(:editing_test_case_id, nil)
      |> assign(:test_case_form, nil)
      |> assign(:editing_test_case_params, nil)
      |> assign(:editing_suite_metadata, false)
      |> assign(:assertion_edit_mode, %{})

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("populate_from_dataset", %{"dataset_import" => params}, socket) do
    case Datasets.get_dataset(params["dataset_id"]) do
      nil ->
        {:noreply, assign(socket, :dataset_import_status, "Dataset not found")}

      dataset ->
        populate_from_dataset(socket, dataset)
    end
  end

  @impl Phoenix.LiveView
  def handle_event("edit_suite_metadata", _params, socket) do
    changeset = Evals.change_suite(socket.assigns.suite)

    {:noreply,
     socket
     |> assign(:editing_suite_metadata, true)
     |> assign(:suite_form, to_form(changeset))}
  end

  @impl Phoenix.LiveView
  def handle_event("cancel_edit_suite_metadata", _params, socket) do
    {:noreply, assign(socket, :editing_suite_metadata, false)}
  end

  @impl Phoenix.LiveView
  def handle_event("validate_suite_metadata", %{"suite" => suite_params}, socket) do
    changeset =
      socket.assigns.suite
      |> Evals.change_suite(suite_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :suite_form, to_form(changeset))}
  end

  @impl Phoenix.LiveView
  def handle_event("save_suite_metadata", %{"suite" => suite_params}, socket) do
    # Handle empty string as nil for optional project_id
    suite_params =
      Map.update(suite_params, "project_id", nil, fn
        "" -> nil
        val -> val
      end)

    case Evals.update_suite(socket.assigns.suite, suite_params) do
      {:ok, suite} ->
        prompt = Prompts.get_prompt_with_versions!(suite.prompt_id)
        default_version_id = List.first(prompt.versions) |> then(&if &1, do: &1.id, else: nil)

        {:noreply,
         socket
         |> assign(:suite, suite)
         |> assign(:prompt, prompt)
         |> assign(:selected_version_id, default_version_id)
         |> assign(:selected_prompt_version, selected_prompt_version(prompt, default_version_id))
         |> assign(:page_title, suite.name)
         |> assign(
           :run_suite_form,
           build_run_suite_form(default_version_id, socket.assigns.selected_provider_id)
         )
         |> assign(:editing_suite_metadata, false)
         |> put_flash(:info, "Suite updated successfully")}

      {:error, changeset} ->
        {:noreply, assign(socket, :suite_form, to_form(changeset))}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("select_version", %{"version_id" => version_id}, socket) do
    {:noreply,
     socket
     |> assign(:selected_version_id, version_id)
     |> assign(
       :selected_prompt_version,
       selected_prompt_version(socket.assigns.prompt, version_id)
     )
     |> assign(
       :run_suite_form,
       build_run_suite_form(version_id, socket.assigns.selected_provider_id)
     )}
  end

  @impl Phoenix.LiveView
  def handle_event("select_provider", %{"provider_id" => provider_id}, socket) do
    {:noreply,
     socket
     |> assign(:selected_provider_id, provider_id)
     |> assign(
       :run_suite_form,
       build_run_suite_form(socket.assigns.selected_version_id, provider_id)
     )}
  end

  @impl Phoenix.LiveView
  def handle_event("validate_run_suite", %{"run_suite" => run_suite_params}, socket) do
    version_id = Map.get(run_suite_params, "version_id")
    provider_id = Map.get(run_suite_params, "provider_id")

    {:noreply,
     socket
     |> assign(:selected_version_id, version_id)
     |> assign(:selected_provider_id, provider_id)
     |> assign(
       :selected_prompt_version,
       selected_prompt_version(socket.assigns.prompt, version_id)
     )
     |> assign(:run_suite_form, to_form(run_suite_params, as: :run_suite))}
  end

  @impl Phoenix.LiveView
  def handle_event("toggle_assertion_mode", %{"id" => id}, socket) do
    current_mode = Map.get(socket.assigns.assertion_edit_mode, id, :visual)
    socket = maybe_sync_editing_assertions_json(socket, id, current_mode)
    new_mode = if current_mode == :visual, do: :json, else: :visual
    new_modes = Map.put(socket.assigns.assertion_edit_mode, id, new_mode)
    {:noreply, assign(socket, :assertion_edit_mode, new_modes)}
  end

  @impl Phoenix.LiveView
  def handle_event("add_assertion", %{"id" => _id}, socket) do
    new_assertions = socket.assigns.editing_assertions ++ [%{"type" => "contains", "value" => ""}]
    {:noreply, sync_editing_assertions(socket, new_assertions)}
  end

  @impl Phoenix.LiveView
  def handle_event("remove_assertion", %{"index" => index_str, "id" => _id}, socket) do
    index = String.to_integer(index_str)
    new_assertions = List.delete_at(socket.assigns.editing_assertions, index)
    {:noreply, sync_editing_assertions(socket, new_assertions)}
  end

  @impl Phoenix.LiveView
  def handle_event("add_test_case", _params, socket) do
    case TestCaseEditor.create_test_case(socket.assigns.suite.id, socket.assigns.prompt) do
      {:ok, _test_case} ->
        suite = Evals.get_suite_with_test_cases_and_prompt!(socket.assigns.suite.id)

        {:noreply,
         socket
         |> assign(:suite, suite)
         |> put_flash(:info, "Test case created")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create test case")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("toggle_test_case_import", _params, socket) do
    socket =
      if socket.assigns.show_test_case_import do
        reset_test_case_import(socket)
      else
        assign(socket, :show_test_case_import, true)
      end

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("validate_test_case_import", _params, socket) do
    {:noreply, assign(socket, :test_case_import_preview, nil)}
  end

  @impl Phoenix.LiveView
  def handle_event("cancel_test_case_import_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :test_case_import, ref)}
  end

  @impl Phoenix.LiveView
  def handle_event("preview_test_case_import", _params, socket) do
    results =
      consume_uploaded_entries(socket, :test_case_import, fn %{path: path}, entry ->
        {:ok, parse_test_case_import(path, entry.client_name)}
      end)

    socket =
      case results do
        [{:ok, preview}] ->
          socket
          |> assign(:test_case_import_preview, preview)
          |> clear_flash(:error)

        [{:error, message}] ->
          socket
          |> assign(:test_case_import_preview, nil)
          |> put_flash(:error, message)

        [] ->
          put_flash(socket, :error, "Choose a CSV or JSON file to preview")
      end

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event(
        "confirm_test_case_import",
        _params,
        %{assigns: %{uploads: %{test_case_import: %{entries: [_entry | _entries]}}}} = socket
      ) do
    {:noreply,
     socket
     |> assign(:test_case_import_preview, nil)
     |> put_flash(:error, "Preview the selected file before importing")}
  end

  def handle_event("confirm_test_case_import", _params, socket) do
    case socket.assigns.test_case_import_preview do
      %{summary: %{test_cases: []}} ->
        {:noreply, put_flash(socket, :error, "No valid test cases are available to import")}

      %{summary: %{test_cases: test_case_attrs, rejected: rejected}} ->
        case Evals.import_test_cases(socket.assigns.suite, test_case_attrs) do
          {:ok, test_cases} ->
            suite = Evals.get_suite_with_test_cases_and_prompt!(socket.assigns.suite.id)

            {:noreply,
             socket
             |> assign(:suite, suite)
             |> reset_test_case_import()
             |> put_flash(:info, import_success_message(length(test_cases), rejected))}

          {:error, %{row: row}} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "Import could not save valid row #{row}; no rows were added"
             )}
        end

      nil ->
        {:noreply, put_flash(socket, :error, "Preview a CSV or JSON file before importing")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("edit_test_case", %{"id" => id}, socket) do
    test_case = Evals.get_test_case!(id)
    form_params = TestCaseEditor.build_form_params(test_case)

    socket =
      socket
      |> assign(:editing_test_case_id, id)
      |> assign(:editing_assertions, test_case.assertions)
      |> assign(:editing_test_case_params, form_params)
      |> assign(:test_case_form, to_form(TestCaseEditor.change_form(form_params), as: :test_case))
      |> allow_upload(:documents,
        accept: ~w(.pdf .png .jpg .jpeg .csv .json .txt),
        max_entries: 5,
        max_file_size: 10_000_000
      )

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("cancel_edit", _params, socket) do
    socket =
      socket
      |> assign(:editing_test_case_id, nil)
      |> assign(:editing_assertions, nil)
      |> assign(:test_case_form, nil)
      |> assign(:editing_test_case_params, nil)

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("validate_test_case", %{"test_case" => test_case_params}, socket) do
    edit_mode = Map.get(socket.assigns.assertion_edit_mode, test_case_params["id"], :visual)
    test_case_params = sanitize_test_case_params(test_case_params, edit_mode, socket)

    socket =
      if edit_mode == :visual do
        case AssertionParser.preview_visual(test_case_params) do
          {:ok, assertions} ->
            form_params = merge_visual_assertion_form_params(test_case_params, assertions)

            socket
            |> assign(:editing_test_case_params, form_params)
            |> assign(:editing_assertions, assertions)
            |> assign(
              :test_case_form,
              to_form(TestCaseEditor.change_form(form_params, action: :validate), as: :test_case)
            )

          {:error, message} ->
            socket
            |> assign(:editing_test_case_params, test_case_params)
            |> assign(
              :test_case_form,
              to_form(
                TestCaseEditor.change_form(
                  test_case_params,
                  action: :validate,
                  assertion_error: message
                ),
                as: :test_case
              )
            )
        end
      else
        socket
        |> assign(:editing_test_case_params, test_case_params)
        |> assign(
          :test_case_form,
          to_form(TestCaseEditor.change_form(test_case_params, action: :validate), as: :test_case)
        )
      end

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("save_test_case", %{"test_case" => test_case_params}, socket) do
    id = test_case_params["id"]
    test_case = Evals.get_test_case!(id)
    edit_mode = Map.get(socket.assigns.assertion_edit_mode, id, :visual)
    test_case_params = sanitize_test_case_params(test_case_params, edit_mode, socket)

    case TestCaseEditor.update_test_case(test_case, test_case_params, edit_mode) do
      {:ok, _test_case} ->
        {successful_uploads, failed_uploads} = handle_test_case_uploads(socket, test_case)
        suite = Evals.get_suite_with_test_cases_and_prompt!(socket.assigns.suite.id)

        socket =
          socket
          |> assign(:suite, suite)
          |> assign(:editing_test_case_id, nil)
          |> assign(:editing_assertions, nil)
          |> assign(:test_case_form, nil)
          |> assign(:editing_test_case_params, nil)

        {:noreply, put_upload_flash(socket, successful_uploads, failed_uploads)}

      {:error, message} when is_binary(message) ->
        {:noreply,
         socket
         |> sync_preview_assertions(edit_mode, test_case_params)
         |> assign(
           :test_case_form,
           to_form(
             TestCaseEditor.change_form(
               test_case_params,
               action: :validate,
               assertion_error: message
             ),
             as: :test_case
           )
         )
         |> assign(:editing_test_case_params, test_case_params)
         |> put_flash(:error, message)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update test case")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("delete_document", %{"doc-id" => doc_id, "id" => _test_case_id}, socket) do
    document = Evals.get_test_case_document!(doc_id)

    case Evals.delete_test_case_document(document) do
      {:ok, _} ->
        suite = Evals.get_suite_with_test_cases_and_prompt!(socket.assigns.suite.id)

        {:noreply,
         socket
         |> assign(:suite, suite)
         |> put_flash(:info, "Document deleted successfully")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete document")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("delete_test_case", %{"id" => id}, socket) do
    test_case = Evals.get_test_case!(id)

    case Evals.delete_test_case(test_case) do
      {:ok, _} ->
        suite = Evals.get_suite_with_test_cases_and_prompt!(socket.assigns.suite.id)

        {:noreply,
         socket
         |> assign(:suite, suite)
         |> put_flash(:info, "Test case deleted successfully")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete test case")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("run_suite", %{"run_suite" => run_suite_params}, socket) do
    # Prevent concurrent runs
    if socket.assigns.running do
      {:noreply, put_flash(socket, :error, "Suite is already running")}
    else
      version_id = Map.get(run_suite_params, "version_id", socket.assigns.selected_version_id)
      provider_id = Map.get(run_suite_params, "provider_id", socket.assigns.selected_provider_id)
      {:noreply, start_suite_execution(socket, version_id, provider_id)}
    end
  end

  @impl Phoenix.LiveView
  def handle_event(
        "retry_suite_result",
        %{"suite-run-id" => suite_run_id, "test-case-id" => test_case_id},
        socket
      ) do
    socket =
      if socket.assigns.running do
        put_flash(socket, :error, "Suite is already running")
      else
        retry_suite_result(socket, suite_run_id, test_case_id)
      end

    {:noreply, socket}
  end

  defp parse_test_case_import(path, client_name) do
    case File.read(path) do
      {:ok, payload} ->
        case client_name |> Path.extname() |> String.downcase() do
          ".csv" -> TestCaseImporter.parse_csv(payload)
          ".json" -> TestCaseImporter.parse_json(payload)
          _extension -> {:error, "Import file must be CSV or JSON"}
        end

      {:error, _reason} ->
        {:error, "Import file could not be read"}
    end
  end

  defp reset_test_case_import(socket) do
    socket =
      Enum.reduce(socket.assigns.uploads.test_case_import.entries, socket, fn entry, socket ->
        cancel_upload(socket, :test_case_import, entry.ref)
      end)

    socket
    |> assign(:show_test_case_import, false)
    |> assign(:test_case_import_preview, nil)
  end

  defp import_success_message(created, 0) do
    "Imported #{created} test case(s)"
  end

  defp import_success_message(created, rejected) do
    "Imported #{created} test case(s); #{rejected} row(s) were rejected"
  end

  defp handle_test_case_uploads(socket, test_case) do
    socket
    |> consume_uploaded_entries(:documents, fn %{path: path}, entry ->
      {:ok, DocumentIngestion.ingest(path, entry, test_case.id)}
    end)
    |> Enum.split_with(&successful_upload?/1)
  end

  defp successful_upload?({:success, _}), do: true
  defp successful_upload?(_), do: false

  defp put_upload_flash(socket, successful_uploads, failed_uploads)
       when failed_uploads != [] and successful_uploads == [] do
    failed_files =
      Enum.map_join(failed_uploads, ", ", fn {:failed, name, reason} ->
        "#{name} (#{reason})"
      end)

    put_flash(
      socket,
      :error,
      "Test case updated but document uploads failed: #{failed_files}"
    )
  end

  defp put_upload_flash(socket, successful_uploads, failed_uploads) when failed_uploads != [] do
    failed_count = length(failed_uploads)
    success_count = length(successful_uploads)

    put_flash(
      socket,
      :warning,
      "Test case updated with #{success_count} document(s), but #{failed_count} failed validation"
    )
  end

  defp put_upload_flash(socket, successful_uploads, _failed_uploads)
       when successful_uploads != [] do
    put_flash(
      socket,
      :info,
      "Test case updated with #{length(successful_uploads)} document(s)"
    )
  end

  defp put_upload_flash(socket, _successful_uploads, _failed_uploads) do
    put_flash(socket, :info, "Test case updated successfully")
  end

  @impl Phoenix.LiveView
  def handle_info({:suite_completed, {:ok, suite_run}}, socket) do
    # Suite run comes from execute_suite which returns it after insert,
    # so we need to preload associations here since it's not from a context query
    suite_run = Evals.reload_suite_run_with_associations(suite_run)

    {:noreply,
     socket
     |> assign(:suite_runs, [suite_run | socket.assigns.suite_runs])
     |> clear_run_task_state()
     |> put_flash(:info, "Suite executed successfully")}
  end

  @impl Phoenix.LiveView
  def handle_info({:suite_completed, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> clear_run_task_state()
     |> put_flash(:error, suite_execution_error_message(reason))}
  end

  @impl Phoenix.LiveView
  def handle_info(
        {:DOWN, monitor_ref, :process, _pid, reason},
        %{assigns: %{run_task_monitor_ref: monitor_ref}} = socket
      ) do
    if reason == :normal do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> clear_run_task_state()
       |> put_flash(:error, "Suite execution crashed before completion")}
    end
  end

  defp relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 ->
        "just now"

      diff < 3600 ->
        minutes = div(diff, 60)
        "#{minutes} #{if minutes == 1, do: "minute", else: "minutes"} ago"

      diff < 86_400 ->
        hours = div(diff, 3600)
        "#{hours} #{if hours == 1, do: "hour", else: "hours"} ago"

      diff < 604_800 ->
        days = div(diff, 86_400)
        "#{days} #{if days == 1, do: "day", else: "days"} ago"

      true ->
        Calendar.strftime(datetime, "%B %d, %Y")
    end
  end

  defp build_run_suite_form(version_id, provider_id) do
    to_form(
      %{
        "version_id" => version_id,
        "provider_id" => provider_id
      },
      as: :run_suite
    )
  end

  defp selected_prompt_version(%{versions: versions}, version_id) when is_list(versions) do
    Enum.find(versions, List.first(versions), fn version ->
      to_string(version.id) == to_string(version_id)
    end)
  end

  defp assertion_result_rows(assertion_results) when is_list(assertion_results) do
    Enum.flat_map(assertion_results, &assertion_result_rows_for_assertion/1)
  end

  defp assertion_result_rows(_assertion_results), do: []

  defp assertion_result_rows_for_assertion(%{"type" => "json_deep_compare"} = assertion) do
    assertion
    |> get_in(["score_details", "comparisons"])
    |> deep_compare_rows()
  end

  defp assertion_result_rows_for_assertion(%{"type" => "json_field"} = assertion) do
    [
      %{
        detail: get_in(assertion, ["value", "field"]),
        expected: get_in(assertion, ["value", "expected"]),
        actual: Map.get(assertion, "actual_value"),
        passed: assertion["passed"]
      }
    ]
  end

  defp assertion_result_rows_for_assertion(assertion) do
    [
      %{
        detail: assertion["type"],
        expected: assertion["value"],
        actual: nil,
        passed: assertion["passed"]
      }
    ]
  end

  defp judge_source_label(%{"template" => template_id}) do
    case JudgeCatalog.fetch(template_id) do
      {:ok, template} -> template.name
      :error -> template_id
    end
  end

  defp judge_source_label(%{"rubric" => _rubric}) do
    "Custom rubric"
  end

  defp judge_source_label(_assertion) do
    "Invalid configuration"
  end

  defp judge_provider_name(providers, provider_id) do
    case Enum.find(providers, &(&1.id == provider_id)) do
      nil -> "Unavailable provider (#{provider_id})"
      provider -> provider.name
    end
  end

  defp deep_compare_rows(comparisons) when is_map(comparisons) do
    comparisons
    |> Enum.sort_by(fn {path, _details} -> path end)
    |> Enum.map(fn {path, details} ->
      %{
        detail: path,
        expected: details["expected"],
        actual: details["actual"],
        passed: details["passed"]
      }
    end)
  end

  defp deep_compare_rows(_comparisons), do: []

  defp format_score(%Decimal{} = score) do
    score
    |> Decimal.to_float()
    |> format_score()
  end

  defp format_score(score) when is_integer(score), do: format_score(score / 1)
  defp format_score(score) when is_float(score), do: :erlang.float_to_binary(score, decimals: 1)
  defp format_score(_score), do: nil

  defp display_value(nil), do: "null"
  defp display_value(value) when is_binary(value), do: value

  defp display_value(value) when is_integer(value) or is_float(value) or is_boolean(value),
    do: inspect(value)

  defp display_value(value) when is_map(value) or is_list(value), do: Jason.encode!(value)
  defp display_value(value), do: to_string(value)

  defp sync_editing_assertions(socket, assertions) do
    form_params =
      (socket.assigns.editing_test_case_params || %{})
      |> Map.take(["id", "variable_values"])
      |> Map.merge(AssertionParser.build_form_params(assertions))

    socket
    |> assign(:editing_assertions, assertions)
    |> assign(:editing_test_case_params, form_params)
    |> assign(:test_case_form, to_form(TestCaseEditor.change_form(form_params), as: :test_case))
  end

  defp sync_preview_assertions(socket, :visual, test_case_params) do
    case AssertionParser.preview_visual(test_case_params) do
      {:ok, assertions} -> assign(socket, :editing_assertions, assertions)
      {:error, _preview_error} -> socket
    end
  end

  defp sync_preview_assertions(socket, _edit_mode, _test_case_params), do: socket

  defp maybe_sync_editing_assertions_json(socket, id, :visual) do
    case socket.assigns do
      %{editing_test_case_id: ^id, editing_test_case_params: %{} = test_case_params} ->
        case AssertionParser.preview_visual(test_case_params) do
          {:ok, assertions} ->
            assign(
              socket,
              :editing_test_case_params,
              merge_visual_assertion_form_params(test_case_params, assertions)
            )

          {:error, _preview_error} ->
            socket
        end

      _other ->
        socket
    end
  end

  defp maybe_sync_editing_assertions_json(socket, _id, _mode), do: socket

  defp merge_visual_assertion_form_params(test_case_params, assertions) do
    assertion_params =
      test_case_params
      |> Map.get("assertions", %{})
      |> normalize_assertion_params()

    test_case_params
    |> Map.take(["id", "variable_values"])
    |> Map.merge(AssertionParser.build_form_params(assertions))
    |> Map.put("assertions", assertion_params)
  end

  defp sanitize_test_case_params(test_case_params, :visual, socket) do
    allowed_indices =
      (socket.assigns.editing_assertions || [])
      |> Enum.with_index()
      |> Enum.map(fn {_assertion, idx} -> idx end)
      |> MapSet.new()

    assertion_params =
      test_case_params
      |> Map.get("assertions", %{})
      |> normalize_assertion_params()
      |> Enum.filter(fn {key, _value} -> keep_assertion_param?(key, allowed_indices) end)
      |> Map.new()

    Map.put(test_case_params, "assertions", assertion_params)
  end

  defp sanitize_test_case_params(test_case_params, _edit_mode, _socket), do: test_case_params

  defp normalize_assertion_params(params) when is_map(params), do: params
  defp normalize_assertion_params(params) when is_list(params), do: Map.new(params)
  defp normalize_assertion_params(_params), do: %{}

  defp keep_assertion_param?(key, allowed_indices) when is_binary(key) do
    case Regex.run(~r/_(\d+)$/, key, capture: :all_but_first) do
      [idx] ->
        case Integer.parse(idx) do
          {parsed_idx, ""} -> MapSet.member?(allowed_indices, parsed_idx)
          _ -> true
        end

      _ ->
        true
    end
  end

  defp assertion_type_value(assertion, test_case_params, idx) do
    assertion_form_value(test_case_params, idx, "type") || assertion["type"] || "contains"
  end

  defp assertion_text_value(assertion, test_case_params, idx, field_name, assertion_key) do
    case assertion_form_value(test_case_params, idx, field_name) || assertion[assertion_key] do
      nil -> ""
      value -> display_value(value)
    end
  end

  defp assertion_expected_json_value_for_json_field(assertion, test_case_params, idx) do
    case assertion_form_value(test_case_params, idx, "expected_json_value") do
      nil ->
        Jason.encode!(Map.get(assertion, "expected", ""))

      value ->
        value
    end
  end

  defp assertion_expected_json_value(assertion, test_case_params, idx) do
    case assertion_form_value(test_case_params, idx, "expected_json") do
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

  defp assertion_threshold_value(assertion, test_case_params, idx) do
    case assertion_form_value(test_case_params, idx, "threshold") do
      nil ->
        if is_number(assertion["threshold"]), do: to_string(assertion["threshold"]), else: ""

      value ->
        value
    end
  end

  defp assertion_rubric_source_value(assertion, test_case_params, idx) do
    case assertion_form_value(test_case_params, idx, "rubric_source") do
      nil -> if is_binary(assertion["rubric"]), do: "custom", else: "template"
      value -> value
    end
  end

  defp assertion_evidence_json_value(assertion, test_case_params, idx, field_name) do
    case assertion_form_value(test_case_params, idx, "#{field_name}_json_value") do
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

  defp assertion_form_value(nil, _idx, _field_name), do: nil

  defp assertion_form_value(test_case_params, idx, field_name) do
    test_case_params
    |> Map.get("assertions", %{})
    |> normalize_assertion_params()
    |> Map.get("assertion_#{field_name}_#{idx}")
  end

  defp retry_count(%{"retry_count" => count}) when is_integer(count), do: count

  defp retry_count(%{"retry_count" => count}) when is_binary(count) do
    case Integer.parse(count) do
      {parsed, ""} -> parsed
      _ -> 0
    end
  end

  defp retry_count(_result), do: 0

  defp retried_at(%{"retried_at" => retried_at}) when is_binary(retried_at) do
    case DateTime.from_iso8601(retried_at) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp retried_at(_result), do: nil

  defp retry_suite_result(socket, suite_run_id, test_case_id) do
    with {:ok, suite_run} <- fetch_loaded_suite_run(socket.assigns.suite_runs, suite_run_id),
         {:ok, updated_suite_run} <- Evals.retry_suite_run_test_case(suite_run, test_case_id) do
      updated_suite_run = Evals.reload_suite_run_with_associations(updated_suite_run)

      socket
      |> assign(:suite_runs, replace_suite_run(socket.assigns.suite_runs, updated_suite_run))
      |> put_flash(:info, "Test case retried successfully")
    else
      {:error, reason} ->
        put_flash(socket, :error, retry_result_error_message(reason))
    end
  end

  defp fetch_loaded_suite_run(suite_runs, suite_run_id) do
    case Enum.find(suite_runs, &(&1.id == suite_run_id)) do
      nil -> {:error, :suite_run_not_found}
      suite_run -> {:ok, suite_run}
    end
  end

  defp replace_suite_run(suite_runs, updated_suite_run) do
    Enum.map(suite_runs, fn suite_run ->
      if suite_run.id == updated_suite_run.id, do: updated_suite_run, else: suite_run
    end)
  end

  defp clear_run_task_state(socket) do
    case socket.assigns.run_task_monitor_ref do
      nil ->
        assign(socket, :running, false)

      monitor_ref ->
        Process.demonitor(monitor_ref, [:flush])

        socket
        |> assign(:run_task_monitor_ref, nil)
        |> assign(:running, false)
    end
  end

  defp start_suite_execution(socket, version_id, provider_id) do
    case Evals.launch_suite_execution(
           self(),
           socket.assigns.suite.id,
           version_id,
           provider_id
         ) do
      {:ok, monitor_ref} ->
        socket
        |> assign(:run_task_monitor_ref, monitor_ref)
        |> assign(:running, true)

      {:error, _reason} ->
        put_flash(socket, :error, "Failed to start suite execution")
    end
  end

  defp suite_execution_error_message(:suite_not_found),
    do: "Failed to execute suite: suite not found"

  defp suite_execution_error_message(:prompt_version_not_found),
    do: "Failed to execute suite: prompt version not found"

  defp suite_execution_error_message(:provider_not_found),
    do: "Failed to execute suite: provider not found"

  defp suite_execution_error_message({:execution_failed, detail}),
    do: "Failed to execute suite: #{format_execution_error_detail(detail)}"

  defp suite_execution_error_message(_reason), do: "Failed to execute suite"

  defp retry_result_error_message(:test_case_result_not_found),
    do: "Failed to retry test case: existing result not found"

  defp retry_result_error_message(:suite_run_not_found),
    do: "Failed to retry test case: suite run not found"

  defp retry_result_error_message(:test_case_not_found),
    do: "Failed to retry test case: test case not found"

  defp retry_result_error_message(:prompt_version_not_found),
    do: "Failed to retry test case: prompt version not found"

  defp retry_result_error_message(:provider_not_found),
    do: "Failed to retry test case: provider not found"

  defp retry_result_error_message({:retry_failed, detail}),
    do: "Failed to retry test case: #{format_execution_error_detail(detail)}"

  defp retry_result_error_message(_reason), do: "Failed to retry test case"

  defp format_execution_error_detail(detail) when is_binary(detail), do: detail
  defp format_execution_error_detail(detail), do: inspect(detail)

  defp populate_from_dataset(socket, dataset) do
    case Datasets.populate_suite(dataset, socket.assigns.suite) do
      {:ok, []} ->
        {:noreply,
         assign(
           socket,
           :dataset_import_status,
           "All entries from #{dataset.name} were already imported"
         )}

      {:ok, test_cases} ->
        suite = Evals.get_suite_with_test_cases_and_prompt!(socket.assigns.suite.id)

        {:noreply,
         socket
         |> assign(:suite, suite)
         |> assign(
           :dataset_import_status,
           "Imported #{length(test_cases)} #{entry_label(test_cases)} from #{dataset.name}"
         )
         |> put_flash(:info, "Dataset entries imported")}

      {:error, _reason} ->
        {:noreply, assign(socket, :dataset_import_status, "Dataset import failed")}
    end
  end

  defp entry_label([_test_case]) do
    "entry"
  end

  defp entry_label(_test_cases) do
    "entries"
  end
end
