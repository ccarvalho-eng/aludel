defmodule Aludel.Web.SuiteLive.ShowTest do
  use Aludel.Web.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest
  import Aludel.EvalsFixtures
  import Aludel.PromptsFixtures
  import Aludel.ProvidersFixtures
  import Mox

  alias Aludel.Evals
  alias Aludel.Interfaces.HttpClientMock

  test "displays suite details", %{conn: conn} do
    prompt = prompt_fixture(%{name: "Test Prompt"})
    suite = suite_fixture(%{name: "Test Suite", prompt_id: prompt.id})

    {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

    assert render(view) =~ "Test Suite"
    assert render(view) =~ "Test Prompt"
  end

  test "lists test cases", %{conn: conn} do
    suite = suite_fixture()
    _test_case = test_case_fixture(%{suite_id: suite.id})

    {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

    assert has_element?(view, "#test-cases")
  end

  test "has run suite button", %{conn: conn} do
    suite = suite_fixture()

    {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

    assert has_element?(view, "#run-suite-btn")
  end

  describe "test case import" do
    test "previews accepted and rejected rows before confirmed persistence", %{conn: conn} do
      suite = suite_fixture()
      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      view
      |> element("#toggle-test-case-import")
      |> render_click()

      assert has_element?(view, "#test-case-import-panel")

      payload = "input,expected,assertion\nfirst,ok,contains\nbad,,contains\n"

      upload =
        file_input(view, "#test-case-import-form", :test_case_import, [
          %{name: "cases.csv", content: payload, type: "text/csv"}
        ])

      render_upload(upload, "cases.csv")

      view
      |> form("#test-case-import-form")
      |> render_submit()

      assert has_element?(view, "#test-case-import-preview")
      assert has_element?(view, "#test-case-import-valid-count", "1")
      assert has_element?(view, "#test-case-import-rejected-count", "1")
      assert has_element?(view, "#test-case-import-error-3", "expected is required")
      assert Evals.get_suite_with_test_cases!(suite.id).test_cases == []

      view
      |> element("#confirm-test-case-import")
      |> render_click()

      assert has_element?(view, "#flash-info", "Imported 1 test case(s); 1 row(s) were rejected")

      assert [%{variable_values: %{"input" => "first"}}] =
               Evals.get_suite_with_test_cases!(suite.id).test_cases

      refute has_element?(view, "#test-case-import-panel")
    end

    test "keeps malformed JSON recoverable in the import panel", %{conn: conn} do
      suite = suite_fixture()
      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      view
      |> element("#toggle-test-case-import")
      |> render_click()

      upload =
        file_input(view, "#test-case-import-form", :test_case_import, [
          %{name: "cases.json", content: "{invalid}", type: "application/json"}
        ])

      render_upload(upload, "cases.json")

      view
      |> form("#test-case-import-form")
      |> render_submit()

      assert has_element?(view, "#flash-error", "Invalid JSON payload")
      assert has_element?(view, "#test-case-import-panel")
      refute has_element?(view, "#test-case-import-preview")
      assert Process.alive?(view.pid)
    end

    test "clears a stale preview when a replacement file is selected", %{conn: conn} do
      suite = suite_fixture()
      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      view
      |> element("#toggle-test-case-import")
      |> render_click()

      initial_upload =
        file_input(view, "#test-case-import-form", :test_case_import, [
          %{
            name: "initial.csv",
            content: "input,expected,assertion\nfirst,ok,contains\n",
            type: "text/csv"
          }
        ])

      render_upload(initial_upload, "initial.csv")

      view
      |> form("#test-case-import-form")
      |> render_submit()

      assert has_element?(view, "#test-case-import-preview")

      replacement_upload =
        file_input(view, "#test-case-import-form", :test_case_import, [
          %{
            name: "replacement.json",
            content: ~s([{"input":"second","expected":"ok","assertion":"contains"}]),
            type: "application/json"
          }
        ])

      render_upload(replacement_upload, "replacement.json")

      refute has_element?(view, "#test-case-import-preview")
      refute has_element?(view, "#confirm-test-case-import")
      assert Evals.get_suite_with_test_cases!(suite.id).test_cases == []
    end
  end

  describe "visual test case display" do
    test "displays variables in readable format", %{conn: conn} do
      suite = suite_fixture()

      _test_case =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"name" => "Alice", "age" => "30"}
        })

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      html = render(view)
      assert html =~ "name"
      assert html =~ "Alice"
      assert html =~ "age"
      assert html =~ "30"
      refute html =~ "inspect("
    end

    test "displays empty state when no variables", %{conn: conn} do
      suite = suite_fixture()
      _test_case = test_case_fixture(%{suite_id: suite.id, variable_values: %{}})

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      assert render(view) =~ "No variables"
    end

    test "displays assertions in readable format", %{conn: conn} do
      suite = suite_fixture()

      _test_case =
        test_case_fixture(%{
          suite_id: suite.id,
          assertions: [
            %{"type" => "contains", "value" => "hello"},
            %{"type" => "regex", "value" => "world.*"}
          ]
        })

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      html = render(view)
      assert html =~ "contains"
      assert html =~ "hello"
      assert html =~ "regex"
      assert html =~ "world.*"
      refute html =~ "%{\"type\""
    end

    test "displays document attachments", %{conn: conn} do
      suite = suite_fixture()
      test_case = test_case_fixture(%{suite_id: suite.id})

      _document =
        test_case_document_fixture(%{
          test_case_id: test_case.id,
          filename: "test.pdf",
          content_type: "application/pdf",
          size_bytes: 1024
        })

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      html = render(view)
      assert html =~ "test.pdf"
      assert html =~ "1024"
    end

    test "displays empty state when no documents", %{conn: conn} do
      suite = suite_fixture()
      _test_case = test_case_fixture(%{suite_id: suite.id})

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      assert render(view) =~ "No documents"
    end

    test "has edit button for each test case", %{conn: conn} do
      suite = suite_fixture()
      test_case = test_case_fixture(%{suite_id: suite.id})

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      assert has_element?(view, "[phx-click='edit_test_case'][phx-value-id='#{test_case.id}']")
    end

    test "has delete button for each test case", %{conn: conn} do
      suite = suite_fixture()
      test_case = test_case_fixture(%{suite_id: suite.id})

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      # Delete button now opens a confirmation modal
      assert has_element?(view, "button", "Delete")
      assert has_element?(view, "#confirm-delete-test-case-#{test_case.id}")
    end
  end

  describe "suite metadata editing" do
    test "shows edit button for suite metadata", %{conn: conn} do
      suite = suite_fixture()

      {:ok, _view, html} = live(conn, "/suites/#{suite.id}")

      assert html =~ "Edit Suite Details" or html =~ "edit_suite_metadata"
    end

    test "handles metadata edit interactions", %{conn: conn} do
      prompt1 = prompt_fixture(%{name: "Prompt 1"})
      suite = suite_fixture(%{name: "Original Name", prompt_id: prompt1.id})

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      html =
        view
        |> element("[phx-click='edit_suite_metadata']")
        |> render_click()

      # Edit form appears
      assert html =~ "Cancel" or html =~ "cancel_edit"
    end

    test "uses the shared select component in suite metadata editing", %{conn: conn} do
      prompt1 = prompt_fixture(%{name: "Prompt 1"})
      prompt2 = prompt_fixture(%{name: "Prompt 2"})
      suite = suite_fixture(%{name: "Original Name", prompt_id: prompt1.id})

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      view
      |> element("[phx-click='edit_suite_metadata']")
      |> render_click()

      assert has_element?(view, "#suite_prompt_id-select[phx-hook='CustomSelect']")
      assert has_element?(view, "#suite_prompt_id-select [data-select-option]", prompt2.name)
      assert has_element?(view, "#suite_project_id-select[phx-hook='CustomSelect']")

      assert has_element?(
               view,
               "#suite_project_id-select [data-select-option][data-value='']",
               "No Project"
             )
    end
  end

  describe "version and provider selection" do
    test "shows the app callback execution mode label when configured", %{conn: conn} do
      original_mode = Application.get_env(:aludel, :execution_mode)

      Application.put_env(:aludel, :execution_mode, :callback)

      on_exit(fn ->
        Application.put_env(:aludel, :execution_mode, original_mode)
      end)

      suite = suite_fixture()

      {:ok, _view, html} = live(conn, "/suites/#{suite.id}")

      assert html =~ "Execution Mode"
      assert html =~ "App Callback"
    end

    test "shows version and provider selectors", %{conn: conn} do
      prompt = prompt_fixture_with_version()
      suite = suite_fixture(%{prompt_id: prompt.id})
      _provider = provider_fixture()

      {:ok, view, html} = live(conn, "/suites/#{suite.id}")

      assert html =~ "Version" or html =~ "select_version"
      assert html =~ "Provider" or html =~ "select_provider"
      assert has_element?(view, "#run_suite_version_id-select[phx-hook='CustomSelect']")
      assert has_element?(view, "#run_suite_provider_id-select[phx-hook='CustomSelect']")
    end

    test "selects a specific version", %{conn: conn} do
      prompt = prompt_fixture_with_version(%{template: "Version 1 {{name}}"})
      suite = suite_fixture(%{prompt_id: prompt.id})
      provider = provider_fixture()
      {:ok, _version} = Aludel.Prompts.create_prompt_version(prompt, "Version 2 {{name}}")
      prompt = Aludel.Prompts.get_prompt_with_versions!(prompt.id)
      version_1 = Enum.find(prompt.versions, &(&1.template == "Version 1 {{name}}"))

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      assert has_element?(view, "#selected-prompt-template", "Version 2 {{name}}")

      view
      |> form("#run-suite-form",
        run_suite: %{
          version_id: version_1.id,
          provider_id: provider.id
        }
      )
      |> render_change()

      assert has_element?(view, "#selected-prompt-template", "Version 1 {{name}}")
    end

    test "selects a specific provider", %{conn: conn} do
      suite = suite_fixture()
      provider = provider_fixture()

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      render_click(view, "select_provider", %{"provider_id" => provider.id})

      # Provider selection should update assigns
      state = :sys.get_state(view.pid)
      socket = state.socket
      assert socket.assigns.selected_provider_id == provider.id
    end
  end

  describe "test case editing" do
    test "shows edit button and handles editing", %{conn: conn} do
      suite = suite_fixture()
      test_case = test_case_fixture(%{suite_id: suite.id, variable_values: %{"name" => "Bob"}})

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      html =
        view
        |> element("[phx-click='edit_test_case']")
        |> render_click(%{"id" => test_case.id})

      # Edit form appears with cancel button
      assert html =~ "Cancel" or html =~ "cancel_edit"
      assert html =~ "Save"
    end

    test "saves test case successfully", %{conn: conn} do
      suite = suite_fixture()

      test_case =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"name" => "Bob"},
          assertions: [%{"type" => "contains", "value" => "Hello"}]
        })

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      view
      |> element("[phx-click='edit_test_case']")
      |> render_click(%{"id" => test_case.id})

      view
      |> form("#test-case-form-#{test_case.id}",
        test_case: %{
          id: test_case.id,
          variable_values: %{"name" => "Updated Bob"},
          assertions: %{
            "assertion_type_0" => "contains",
            "assertion_value_0" => "test"
          }
        }
      )
      |> render_submit()

      assert render(view) =~ "Test case updated successfully"
    end
  end

  describe "test case management in show page" do
    test "adds new test case", %{conn: conn} do
      prompt = prompt_fixture_with_version(%{template: "Hello {{name}}"})
      suite = suite_fixture(%{prompt_id: prompt.id})

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      view
      |> element("[phx-click='add_test_case']")
      |> render_click()

      assert render(view) =~ "Test case created"
    end

    test "shows delete button for test case", %{conn: conn} do
      suite = suite_fixture()
      test_case = test_case_fixture(%{suite_id: suite.id})

      {:ok, _view, html} = live(conn, "/suites/#{suite.id}")

      # Delete button exists (behind modal)
      assert html =~ "Delete Test Case" or html =~ "confirm-delete-test-case-#{test_case.id}"
    end
  end

  describe "assertion editing" do
    test "edits a test case with deep compare assertions without crashing", %{conn: conn} do
      suite = suite_fixture()

      test_case =
        test_case_fixture(%{
          suite_id: suite.id,
          assertions: [
            %{
              "type" => "json_deep_compare",
              "expected" => %{
                "status" => "ok",
                "meta" => %{"priority" => "high"},
                "items" => [%{"id" => 1}, %{"id" => 2}]
              },
              "threshold" => 80.0
            }
          ]
        })

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      view
      |> element("[phx-click='edit_test_case'][phx-value-id='#{test_case.id}']")
      |> render_click()

      assert Process.alive?(view.pid)
      assert has_element?(view, "#test-case-form-#{test_case.id}")
      assert has_element?(view, "#deep-compare-fields-#{test_case.id}-0")
      assert has_element?(view, "#test_case_assertion_expected_json_0")
      assert has_element?(view, "#test_case_assertion_threshold_0[value='80.0']")
    end

    test "switches a deep compare assertion to a contains assertion", %{conn: conn} do
      suite = suite_fixture()

      test_case =
        test_case_fixture(%{
          suite_id: suite.id,
          assertions: [
            %{
              "type" => "json_deep_compare",
              "expected" => %{"status" => "ok"},
              "threshold" => 80.0
            }
          ]
        })

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      view
      |> element("[phx-click='edit_test_case'][phx-value-id='#{test_case.id}']")
      |> render_click()

      html =
        render_change(view, "validate_test_case", %{
          "test_case" => %{
            "id" => test_case.id,
            "variable_values" => %{},
            "assertions" => %{
              "assertion_type_0" => "contains",
              "assertion_value_0" => "hello"
            }
          }
        })

      refute html =~ "json_field type requires a non-blank 'field' value"

      html =
        view
        |> form("#test-case-form-#{test_case.id}",
          test_case: %{
            id: test_case.id,
            variable_values: %{},
            assertions: %{
              "assertion_type_0" => "contains",
              "assertion_value_0" => "hello"
            }
          }
        )
        |> render_submit()

      assert html =~ "Test case updated successfully"
    end

    test "toggles deep compare assertions to JSON mode without losing expected payload or threshold",
         %{conn: conn} do
      suite = suite_fixture()

      test_case =
        test_case_fixture(%{
          suite_id: suite.id,
          assertions: [
            %{
              "type" => "json_deep_compare",
              "expected" => %{"status" => "ok"},
              "threshold" => 80.0
            }
          ]
        })

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      view
      |> element("[phx-click='edit_test_case'][phx-value-id='#{test_case.id}']")
      |> render_click()

      render_change(view, "validate_test_case", %{
        "test_case" => %{
          "id" => test_case.id,
          "variable_values" => %{},
          "assertions" => %{
            "assertion_type_0" => "json_deep_compare",
            "assertion_expected_json_0" =>
              ~s({"status":"ok","meta":{"priority":"high"},"items":[{"id":1},{"id":2}]}),
            "assertion_threshold_0" => "82.5"
          }
        }
      })

      render_click(view, "toggle_assertion_mode", %{"id" => test_case.id})

      assertions_json =
        :sys.get_state(view.pid).socket.assigns.editing_test_case_params["assertions_json"]

      assert assertions_json =~ "\"type\": \"json_deep_compare\""
      assert assertions_json =~ "\"threshold\": 82.5"
      assert assertions_json =~ "\"priority\": \"high\""
    end

    test "switches a deep compare assertion to json_field without keeping threshold controls", %{
      conn: conn
    } do
      suite = suite_fixture()

      test_case =
        test_case_fixture(%{
          suite_id: suite.id,
          assertions: [
            %{
              "type" => "json_deep_compare",
              "expected" => %{"status" => "ok"},
              "threshold" => 80.0
            }
          ]
        })

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      view
      |> element("[phx-click='edit_test_case'][phx-value-id='#{test_case.id}']")
      |> render_click()

      render_change(view, "validate_test_case", %{
        "test_case" => %{
          "id" => test_case.id,
          "variable_values" => %{},
          "assertions" => %{
            "assertion_type_0" => "json_field",
            "assertion_field_0" => "status",
            "assertion_expected_0" => "ok",
            "assertion_expected_json_0" => ~s({"status":"ok"}),
            "assertion_threshold_0" => "80.0"
          }
        }
      })

      assert has_element?(view, "#json-fields-#{test_case.id}-0[style*='display: flex']")
      assert has_element?(view, "#test_case_assertion_field_0[value='status']")
      assert has_element?(view, "#test_case_assertion_expected_0[value='ok']")
      refute has_element?(view, "#deep-compare-fields-#{test_case.id}-0")
      refute has_element?(view, "#test-case-assertions-error-#{test_case.id}")
    end

    test "removes a deep compare assertion and adds a new contains assertion", %{conn: conn} do
      suite = suite_fixture()

      test_case =
        test_case_fixture(%{
          suite_id: suite.id,
          assertions: [
            %{
              "type" => "json_deep_compare",
              "expected" => %{"status" => "ok"},
              "threshold" => 80.0
            }
          ]
        })

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      view
      |> element("[phx-click='edit_test_case'][phx-value-id='#{test_case.id}']")
      |> render_click()

      render_click(view, "remove_assertion", %{"index" => "0", "id" => test_case.id})
      render_click(view, "add_assertion", %{"id" => test_case.id})

      html =
        view
        |> form("#test-case-form-#{test_case.id}",
          test_case: %{
            id: test_case.id,
            variable_values: %{},
            assertions: %{
              "assertion_type_0" => "contains",
              "assertion_value_0" => "hello"
            }
          }
        )
        |> render_submit()

      assert html =~ "Test case updated successfully"
    end

    test "shows both json_field inputs for a new assertion row", %{conn: conn} do
      suite = suite_fixture()
      test_case = test_case_fixture(%{suite_id: suite.id, assertions: []})

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      view
      |> element("[phx-click='edit_test_case'][phx-value-id='#{test_case.id}']")
      |> render_click()

      render_click(view, "add_assertion", %{"id" => test_case.id})

      render_change(view, "validate_test_case", %{
        "test_case" => %{
          "id" => test_case.id,
          "variable_values" => %{},
          "assertions" => %{
            "assertion_type_0" => "json_field",
            "assertion_field_0" => "",
            "assertion_expected_0" => ""
          }
        }
      })

      assert has_element?(view, "#json-fields-#{test_case.id}-0[style*='display: flex']")
      assert has_element?(view, "#test_case_assertion_field_0")
      assert has_element?(view, "#test_case_assertion_expected_0")
      refute has_element?(view, "#value-field-#{test_case.id}-0")
      refute has_element?(view, "#test-case-assertions-error-#{test_case.id}")
    end

    test "keeps typed json_field expectations visible and saveable in visual mode", %{conn: conn} do
      suite = suite_fixture()

      test_case =
        test_case_fixture(%{
          suite_id: suite.id,
          assertions: [%{"type" => "json_field", "field" => "count", "expected" => 1}]
        })

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      view
      |> element("[phx-click='edit_test_case'][phx-value-id='#{test_case.id}']")
      |> render_click()

      assert has_element?(view, "#test_case_assertion_expected_0[value='1']")

      html =
        view
        |> form("#test-case-form-#{test_case.id}",
          test_case: %{
            id: test_case.id,
            variable_values: %{},
            assertions: %{
              "assertion_type_0" => "json_field",
              "assertion_field_0" => "count",
              "assertion_expected_0" => "1",
              "assertion_expected_json_value_0" => "1"
            }
          }
        )
        |> render_submit()

      assert html =~ "Test case updated successfully"
    end

    test "shows assertion controls in edit mode", %{conn: conn} do
      suite = suite_fixture()
      test_case = test_case_fixture(%{suite_id: suite.id})

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      html =
        view
        |> element("[phx-click='edit_test_case']")
        |> render_click(%{"id" => test_case.id})

      # Check for assertion controls
      assert html =~ "Assertions" or html =~ "assertion"
      assert html =~ "toggle_assertion_mode" or html =~ "JSON"
    end

    test "toggles assertion mode from visual to JSON", %{conn: conn} do
      suite = suite_fixture()
      test_case = test_case_fixture(%{suite_id: suite.id})

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      view
      |> element("[phx-click='edit_test_case']")
      |> render_click(%{"id" => test_case.id})

      html = render_click(view, "toggle_assertion_mode", %{"id" => test_case.id})

      # Should show JSON textarea
      assert html =~ "assertions_json" or html =~ "JSON"
    end

    test "saves test case with JSON assertions", %{conn: conn} do
      suite = suite_fixture()
      test_case = test_case_fixture(%{suite_id: suite.id, variable_values: %{"name" => "Test"}})

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      view
      |> element("[phx-click='edit_test_case']")
      |> render_click(%{"id" => test_case.id})

      render_click(view, "toggle_assertion_mode", %{"id" => test_case.id})

      html =
        view
        |> form("#test-case-form-#{test_case.id}",
          test_case: %{
            id: test_case.id,
            variable_values: %{"name" => "Test"},
            assertions_json: ~s([{"type": "contains", "value": "test"}])
          }
        )
        |> render_submit()

      assert html =~ "Test case updated successfully"
    end

    test "rejects invalid JSON in assertions", %{conn: conn} do
      suite = suite_fixture()
      test_case = test_case_fixture(%{suite_id: suite.id})

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      view
      |> element("[phx-click='edit_test_case']")
      |> render_click(%{"id" => test_case.id})

      render_click(view, "toggle_assertion_mode", %{"id" => test_case.id})

      html =
        view
        |> form("#test-case-form-#{test_case.id}",
          test_case: %{
            id: test_case.id,
            assertions_json: "{invalid json}"
          }
        )
        |> render_submit()

      assert html =~ "Invalid JSON" or html =~ "syntax"
    end

    test "rejects invalid assertion types in JSON", %{conn: conn} do
      suite = suite_fixture()
      test_case = test_case_fixture(%{suite_id: suite.id})

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      view
      |> element("[phx-click='edit_test_case']")
      |> render_click(%{"id" => test_case.id})

      render_click(view, "toggle_assertion_mode", %{"id" => test_case.id})

      html =
        view
        |> form("#test-case-form-#{test_case.id}",
          test_case: %{
            id: test_case.id,
            assertions_json: ~s([{"type": "invalid_type", "value": "test"}])
          }
        )
        |> render_submit()

      assert html =~ "Invalid assertion type"
    end

    test "does not crash validation when visual assertion indices are invalid", %{conn: conn} do
      suite = suite_fixture()
      test_case = test_case_fixture(%{suite_id: suite.id})

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      view
      |> element("[phx-click='edit_test_case']")
      |> render_click(%{"id" => test_case.id})

      html =
        render_change(view, "validate_test_case", %{
          "test_case" => %{
            "id" => test_case.id,
            "variable_values" => %{},
            "assertions" => %{
              "assertion_type_abc" => "contains",
              "assertion_value_abc" => "hello"
            }
          }
        })

      assert html =~ "Invalid assertion index: abc"
      assert Process.alive?(view.pid)
    end
  end

  describe "suite metadata management" do
    test "saves suite metadata successfully", %{conn: conn} do
      prompt1 = prompt_fixture(%{name: "Prompt 1"})
      prompt2 = prompt_fixture(%{name: "Prompt 2"})
      suite = suite_fixture(%{name: "Original Name", prompt_id: prompt1.id})

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      view
      |> element("[phx-click='edit_suite_metadata']")
      |> render_click()

      assert has_element?(view, "#suite-metadata-form")

      html =
        view
        |> render_click("save_suite_metadata", %{
          "suite" => %{
            "name" => "Updated Name",
            "prompt_id" => prompt2.id
          }
        })

      assert html =~ "Suite updated successfully"
      assert html =~ "Updated Name"
    end

    test "cancels suite metadata editing", %{conn: conn} do
      suite = suite_fixture()

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      view
      |> element("[phx-click='edit_suite_metadata']")
      |> render_click()

      html = render_click(view, "cancel_edit_suite_metadata")

      # Should return to normal view
      assert html =~ suite.name
    end
  end

  describe "test case deletion" do
    test "deletes test case successfully", %{conn: conn} do
      suite = suite_fixture()
      test_case = test_case_fixture(%{suite_id: suite.id})

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      html = render_click(view, "delete_test_case", %{"id" => test_case.id})

      assert html =~ "Test case deleted successfully"
    end
  end

  describe "document management" do
    test "deletes document successfully", %{conn: conn} do
      suite = suite_fixture()
      test_case = test_case_fixture(%{suite_id: suite.id})

      document =
        test_case_document_fixture(%{
          test_case_id: test_case.id,
          filename: "test.pdf"
        })

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      html =
        render_click(view, "delete_document", %{"doc-id" => document.id, "id" => test_case.id})

      assert html =~ "Document deleted successfully"
      refute html =~ "test.pdf"
    end
  end

  describe "suite execution" do
    test "recovers when the background execution task fails", %{conn: conn} do
      prompt = prompt_fixture_with_version()
      suite = suite_fixture(%{prompt_id: prompt.id})
      provider = provider_fixture()
      version = List.first(prompt.versions)
      invalid_provider_id = Ecto.UUID.generate()

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      capture_log(fn ->
        view
        |> element("#run-suite-form")
        |> render_submit(%{
          run_suite: %{
            version_id: version.id,
            provider_id: invalid_provider_id
          }
        })
      end)

      assert_eventually(fn ->
        has_element?(view, "#flash-error", "Failed to execute suite: provider not found")
      end)

      assert_eventually(fn ->
        not has_element?(view, "#run-suite-btn[disabled]")
      end)

      assert has_element?(view, "#run-suite-form option[selected][value='#{provider.id}']")
    end

    test "recovers from an abnormal task down message", %{conn: conn} do
      suite = suite_fixture()

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      monitor_ref = make_ref()

      :sys.replace_state(view.pid, fn state ->
        put_in(state.socket.assigns, %{
          state.socket.assigns
          | running: true,
            run_task_monitor_ref: monitor_ref
        })
      end)

      send(view.pid, {:DOWN, monitor_ref, :process, self(), :boom})

      assert_eventually(fn ->
        has_element?(view, "#flash-error", "Suite execution crashed before completion")
      end)

      assert_eventually(fn ->
        not has_element?(view, "#run-suite-btn[disabled]")
      end)
    end

    test "allows rerunning after a failed attempt", %{conn: conn} do
      prompt = prompt_fixture_with_version()
      suite = suite_fixture(%{prompt_id: prompt.id})
      provider = provider_fixture()
      version = List.first(prompt.versions)

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      capture_log(fn ->
        view
        |> element("#run-suite-form")
        |> render_submit(%{
          run_suite: %{
            version_id: version.id,
            provider_id: Ecto.UUID.generate()
          }
        })
      end)

      assert_eventually(fn ->
        has_element?(view, "#flash-error", "Failed to execute suite: provider not found")
      end)

      view
      |> element("#run-suite-form")
      |> render_submit(%{
        run_suite: %{
          version_id: version.id,
          provider_id: provider.id
        }
      })

      assert_eventually(fn ->
        has_element?(view, "#flash-info", "Suite executed successfully")
      end)

      assert_eventually(fn ->
        not has_element?(view, "#run-suite-btn[disabled]")
      end)
    end
  end

  describe "test case edit cancellation" do
    test "cancels test case editing", %{conn: conn} do
      suite = suite_fixture()
      test_case = test_case_fixture(%{suite_id: suite.id})

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      view
      |> element("[phx-click='edit_test_case']")
      |> render_click(%{"id" => test_case.id})

      html = render_click(view, "cancel_edit")

      # Should return to normal view, not showing edit form
      refute html =~ "Save"
    end
  end

  defp assert_eventually(fun, attempts \\ 200)

  defp assert_eventually(fun, attempts) when attempts > 0 do
    result = fun.()

    if result do
      assert result
    else
      Process.sleep(10)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp assert_eventually(fun, 0) do
    result = fun.()
    assert result
  end

  describe "result copy actions" do
    test "shows copy action for suite result outputs", %{conn: conn} do
      prompt = prompt_fixture_with_version()
      suite = suite_fixture(%{prompt_id: prompt.id})
      prompt = Aludel.Prompts.get_prompt_with_versions!(prompt.id)
      version = hd(prompt.versions)
      provider = provider_fixture(%{name: "OpenAI"})
      test_case = test_case_fixture(%{suite_id: suite.id})

      suite_run =
        suite_run_fixture(%{
          suite_id: suite.id,
          prompt_version_id: version.id,
          provider_id: provider.id,
          passed: 1,
          failed: 0,
          results: [
            %{
              "test_case_id" => test_case.id,
              "passed" => true,
              "output" => "Structured output for copying",
              "assertion_results" => [
                %{"type" => "contains", "passed" => true, "value" => "Structured"}
              ],
              "cost_usd" => 0.001,
              "latency_ms" => 250
            }
          ]
        })

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      assert has_element?(
               view,
               "#suite-result-output-#{suite_run.id}-#{test_case.id}",
               "Structured output for copying"
             )

      assert has_element?(
               view,
               "#copy-suite-result-#{suite_run.id}-#{test_case.id}",
               "Copy output"
             )

      assert has_element?(
               view,
               "#export-suite-run-#{suite_run.id}[href='/suites/runs/#{suite_run.id}/export']",
               "Export JSON"
             )
    end

    test "renders deep compare score details for suite results", %{conn: conn} do
      prompt = prompt_fixture_with_version()
      suite = suite_fixture(%{prompt_id: prompt.id})
      prompt = Aludel.Prompts.get_prompt_with_versions!(prompt.id)
      version = hd(prompt.versions)
      provider = provider_fixture(%{name: "OpenAI"})
      test_case = test_case_fixture(%{suite_id: suite.id})

      suite_run =
        suite_run_fixture(%{
          suite_id: suite.id,
          prompt_version_id: version.id,
          provider_id: provider.id,
          passed: 1,
          failed: 0,
          avg_score: Decimal.new("75.0"),
          results: [
            %{
              "test_case_id" => test_case.id,
              "passed" => true,
              "score" => 75.0,
              "output" => ~s({"status":"ok","count":1,"meta":{"city":"NYC","zip":"10001"}}),
              "assertion_results" => [
                %{
                  "type" => "json_deep_compare",
                  "passed" => true,
                  "score" => 75.0,
                  "reason" => "Deep comparison meets the 70.0% threshold",
                  "metadata" => %{
                    "decoded" => true,
                    "threshold" => 70.0
                  },
                  "value" => %{
                    "expected" => %{
                      "status" => "ok",
                      "count" => 2,
                      "meta" => %{"city" => "NYC", "zip" => "10001"}
                    },
                    "threshold" => 70.0
                  },
                  "score_details" => %{
                    "matches" => 3,
                    "total" => 4,
                    "field_scores" => %{
                      "status" => 1,
                      "count" => 0,
                      "meta.city" => 1,
                      "meta.zip" => 1
                    },
                    "comparisons" => %{
                      "status" => %{"passed" => true, "expected" => "ok", "actual" => "ok"},
                      "count" => %{"passed" => false, "expected" => 2, "actual" => 1},
                      "meta.city" => %{"passed" => true, "expected" => "NYC", "actual" => "NYC"},
                      "meta.zip" => %{
                        "passed" => true,
                        "expected" => "10001",
                        "actual" => "10001"
                      }
                    }
                  }
                }
              ],
              "cost_usd" => 0.001,
              "latency_ms" => 250
            }
          ]
        })

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      assert has_element?(view, "#suite-run-score-#{suite_run.id}", "75.0% avg score")

      assert has_element?(
               view,
               "#suite-result-score-#{suite_run.id}-#{test_case.id}",
               "75.0% match"
             )

      assert has_element?(
               view,
               "#suite-result-metric-reason-#{suite_run.id}-#{test_case.id}-0",
               "Deep comparison meets the 70.0% threshold"
             )

      assert has_element?(
               view,
               "#suite-result-assertions-#{suite_run.id}-#{test_case.id}",
               "meta.city"
             )

      assert has_element?(
               view,
               "#suite-result-assertions-#{suite_run.id}-#{test_case.id}",
               "count"
             )

      assert has_element?(
               view,
               "#suite-result-assertions-#{suite_run.id}-#{test_case.id}",
               "Expected"
             )

      assert has_element?(
               view,
               "#suite-result-assertions-#{suite_run.id}-#{test_case.id}",
               "Actual"
             )

      assert has_element?(
               view,
               "#suite-result-assertions-table-#{suite_run.id}-#{test_case.id}"
             )
    end
  end

  describe "retry test case result" do
    test "retries a single result and refreshes the rendered output", %{conn: conn} do
      prompt = prompt_fixture_with_version(%{template: "Hello {{name}}"})
      suite = suite_fixture(%{prompt_id: prompt.id})
      prompt = Aludel.Prompts.get_prompt_with_versions!(prompt.id)
      version = hd(prompt.versions)

      provider =
        provider_fixture(%{
          name: "OpenAI",
          pricing: %{"input" => 1000.0, "output" => 2000.0}
        })

      test_case =
        test_case_fixture(%{
          suite_id: suite.id,
          variable_values: %{"name" => "Alice"},
          assertions: [%{"type" => "contains", "value" => "Hello"}]
        })

      suite_run =
        suite_run_fixture(%{
          suite_id: suite.id,
          prompt_version_id: version.id,
          provider_id: provider.id,
          passed: 0,
          failed: 1,
          results: [
            %{
              "test_case_id" => test_case.id,
              "passed" => false,
              "output" => "Rate limit exceeded",
              "assertion_results" => [],
              "cost_usd" => nil,
              "latency_ms" => nil
            }
          ]
        })

      {:ok, view, _html} = live(conn, "/suites/#{suite.id}")

      Mox.allow(HttpClientMock, self(), view.pid)

      expect(HttpClientMock, :request, fn _model, prompt, _opts ->
        assert prompt == "Hello Alice"

        {:ok, %{content: "Hello Alice", input_tokens: 5, output_tokens: 10}}
      end)

      assert has_element?(
               view,
               "#retry-suite-result-#{suite_run.id}-#{test_case.id}",
               "Retry"
             )

      html =
        view
        |> element("#retry-suite-result-#{suite_run.id}-#{test_case.id}")
        |> render_click()

      assert html =~ "Test case retried successfully"

      assert has_element?(
               view,
               "#suite-result-output-#{suite_run.id}-#{test_case.id}",
               "Hello Alice"
             )

      assert has_element?(
               view,
               "#suite-result-retry-meta-#{suite_run.id}-#{test_case.id}",
               "Retry #1"
             )
    end
  end
end
