defmodule Aludel.Web.SuiteLive.NewTest do
  use Aludel.Web.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Aludel.PromptsFixtures

  alias Aludel.Evals
  alias Aludel.Projects

  describe "new suite page" do
    test "mounts successfully", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/suites/new")

      assert has_element?(view, "#suite-form")
    end

    test "displays prompt selector", %{conn: conn} do
      _prompt = prompt_fixture(%{name: "Test Prompt"})

      {:ok, view, _html} = live(conn, "/suites/new")

      assert has_element?(view, "#suite_prompt_id-select [data-select-option]", "Test Prompt")
    end

    test "shows add test case button", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/suites/new")

      assert has_element?(view, "button[phx-click='add_test_case']", "Add Test Case")
    end

    test "shows only suite projects in the project select", %{conn: conn} do
      {:ok, _prompt_project} = Projects.create_project(%{name: "Prompt Project", type: :prompt})
      {:ok, _suite_project} = Projects.create_project(%{name: "Suite Project", type: :suite})

      {:ok, view, _html} = live(conn, "/suites/new")

      assert has_element?(view, "#suite_project_id-select [data-select-option]", "Suite Project")
      refute has_element?(view, "#suite_project_id-select [data-select-option]", "Prompt Project")
    end
  end

  describe "prompt selection" do
    test "updates when prompt is selected", %{conn: conn} do
      prompt = prompt_fixture_with_version(%{name: "Test Prompt", template: "Hello {{name}}"})

      {:ok, view, _html} = live(conn, "/suites/new")

      view
      |> form("#suite-form", suite: %{name: "", prompt_id: prompt.id})
      |> render_change()

      assert has_element?(view, "#suite_prompt_id-select [data-select-value]", prompt.name)
      assert has_element?(view, "pre", "Hello {{name}}")
    end

    test "shows prompt selector on mount", %{conn: conn} do
      _prompt = prompt_fixture_with_version(%{name: "Test Prompt"})

      {:ok, view, _html} = live(conn, "/suites/new")

      assert has_element?(
               view,
               "#suite_prompt_id-select [data-select-option][data-value='']",
               "Select a prompt"
             )

      assert has_element?(view, "#suite_prompt_id-select [data-select-option]", "Test Prompt")
    end
  end

  describe "test case management" do
    test "shows add test case button", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/suites/new")

      assert has_element?(view, "button[phx-click='add_test_case']", "Add Test Case")
    end

    test "handles test case interactions", %{conn: conn} do
      prompt = prompt_fixture_with_version(%{template: "Hello {{name}}"})

      {:ok, view, _html} = live(conn, "/suites/new")

      # Select prompt first
      view
      |> form("#suite-form", suite: %{name: "", prompt_id: prompt.id})
      |> render_change()

      # Add test case
      view
      |> element("[phx-click='add_test_case']")
      |> render_click()

      test_case_id = List.first(:sys.get_state(view.pid).socket.assigns.test_cases).id

      assert has_element?(view, "#test_case_#{test_case_id}_var_name")
    end
  end

  describe "assertion management" do
    test "handles assertion interactions", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/suites/new")

      # Add a test case first
      view
      |> element("[phx-click='add_test_case']")
      |> render_click()

      test_case_id = List.first(:sys.get_state(view.pid).socket.assigns.test_cases).id

      assert has_element?(view, "[phx-click='add_assertion'][phx-value-id='#{test_case_id}']")
    end

    test "renders deep compare controls without value input", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/suites/new")

      view
      |> element("[phx-click='add_test_case']")
      |> render_click()

      test_case_id = List.first(:sys.get_state(view.pid).socket.assigns.test_cases).id

      view
      |> render_click("add_assertion", %{"id" => test_case_id})

      view
      |> render_change("validate", %{
        "suite" => %{
          "test_cases" => %{
            test_case_id => %{
              "assertions" => %{
                "assertion_type_0" => "json_deep_compare"
              }
            }
          }
        }
      })

      view
      |> render_change("validate", %{
        "suite" => %{
          "test_cases" => %{
            test_case_id => %{
              "assertions" => %{
                "assertion_type_0" => "json_deep_compare",
                "assertion_expected_json_0" => ~s({"status":"ok"}),
                "assertion_threshold_0" => "80.0"
              }
            }
          }
        }
      })

      assert has_element?(view, "#deep-compare-fields-#{test_case_id}-0")
      assert has_element?(view, "#test_case_#{test_case_id}_assertion_expected_json_0")
      assert has_element?(view, "#test_case_#{test_case_id}_assertion_threshold_0[value='80.0']")
      refute has_element?(view, "#value-field-#{test_case_id}-0")
    end

    test "switches from deep compare to json_field controls", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/suites/new")

      view
      |> element("[phx-click='add_test_case']")
      |> render_click()

      test_case_id = List.first(:sys.get_state(view.pid).socket.assigns.test_cases).id

      view
      |> render_click("add_assertion", %{"id" => test_case_id})

      view
      |> render_change("validate", %{
        "suite" => %{
          "test_cases" => %{
            test_case_id => %{
              "assertions" => %{
                "assertion_type_0" => "json_deep_compare"
              }
            }
          }
        }
      })

      view
      |> render_change("validate", %{
        "suite" => %{
          "test_cases" => %{
            test_case_id => %{
              "assertions" => %{
                "assertion_type_0" => "json_field",
                "assertion_field_0" => "status",
                "assertion_expected_0" => "ok"
              }
            }
          }
        }
      })

      assert has_element?(view, "#json-fields-#{test_case_id}-0")
      assert has_element?(view, "#test_case_#{test_case_id}_assertion_field_0[value='status']")
      assert has_element?(view, "#test_case_#{test_case_id}_assertion_expected_0[value='ok']")
      refute has_element?(view, "#deep-compare-fields-#{test_case_id}-0")
      refute has_element?(view, "#value-field-#{test_case_id}-0")
    end
  end

  describe "suite creation" do
    test "creates suite with test cases successfully", %{conn: conn} do
      prompt = prompt_fixture_with_version(%{template: "Hello {{name}}"})

      {:ok, view, _html} = live(conn, "/suites/new")

      view
      |> form("#suite-form", suite: %{name: "New Suite", prompt_id: prompt.id})
      |> render_change()

      view
      |> element("[phx-click='add_test_case']")
      |> render_click()

      test_case_id = List.first(:sys.get_state(view.pid).socket.assigns.test_cases).id

      view
      |> render_click("add_assertion", %{"id" => test_case_id})

      view
      |> form("#suite-form",
        suite: %{
          name: "New Suite",
          prompt_id: prompt.id,
          test_cases: %{
            test_case_id => %{
              variable_values: %{
                name: "Alice"
              },
              assertions: %{
                assertion_type_0: "contains",
                assertion_value_0: "hello"
              }
            }
          }
        }
      )
      |> render_submit(%{
        "suite" => %{
          "name" => "New Suite",
          "prompt_id" => prompt.id,
          "test_cases" => %{
            test_case_id => %{
              "variable_values" => %{
                "name" => "Alice"
              },
              "assertions" => %{
                "assertion_type_0" => "contains",
                "assertion_value_0" => "hello"
              }
            }
          }
        }
      })

      {_path, flash} = assert_redirect(view)
      assert flash["info"] == "Suite created successfully"
    end

    test "creates suite with uploaded test case documents", %{conn: conn} do
      prompt = prompt_fixture_with_version(%{template: "Hello {{name}}"})

      {:ok, view, _html} = live(conn, "/suites/new")

      view
      |> form("#suite-form", suite: %{name: "Document Suite", prompt_id: prompt.id})
      |> render_change()

      view
      |> element("[phx-click='add_test_case']")
      |> render_click()

      {test_case_id, upload_name} = first_document_upload(view)

      view
      |> render_click("add_assertion", %{"id" => test_case_id})

      upload =
        file_input(view, "#suite-form", upload_name, [
          %{
            name: "context.txt",
            content: "Document context",
            type: "text/plain"
          }
        ])

      render_upload(upload, "context.txt")

      assert has_element?(
               view,
               "#test_case_#{test_case_id}_documents",
               "context.txt"
             )

      view
      |> form("#suite-form",
        suite: %{
          name: "Document Suite",
          prompt_id: prompt.id,
          test_cases: %{
            test_case_id => %{
              variable_values: %{
                name: "Alice"
              },
              assertions: %{
                assertion_type_0: "contains",
                assertion_value_0: "hello"
              }
            }
          }
        }
      )
      |> render_submit(%{
        "suite" => %{
          "name" => "Document Suite",
          "prompt_id" => prompt.id,
          "test_cases" => %{
            test_case_id => %{
              "variable_values" => %{
                "name" => "Alice"
              },
              "assertions" => %{
                "assertion_type_0" => "contains",
                "assertion_value_0" => "hello"
              }
            }
          }
        }
      })

      {path, flash} = assert_redirect(view)
      assert flash["info"] == "Suite created with 1 document(s)"

      [_, suite_id] = Regex.run(~r{/suites/([^/]+)$}, path)
      suite = Evals.get_suite_with_test_cases_and_prompt!(suite_id)
      [created_test_case] = suite.test_cases
      [document] = created_test_case.documents

      assert document.filename == "context.txt"
      assert document.content_type == "text/plain"
      assert document.size_bytes == byte_size("Document context")
    end

    test "reports uploaded document validation failures", %{conn: conn} do
      prompt = prompt_fixture_with_version(%{template: "Hello {{name}}"})

      {:ok, view, _html} = live(conn, "/suites/new")

      view
      |> form("#suite-form", suite: %{name: "Invalid Document Suite", prompt_id: prompt.id})
      |> render_change()

      view
      |> element("[phx-click='add_test_case']")
      |> render_click()

      {test_case_id, upload_name} = first_document_upload(view)

      view
      |> render_click("add_assertion", %{"id" => test_case_id})

      upload =
        file_input(view, "#suite-form", upload_name, [
          %{
            name: "invalid.json",
            content: "not json",
            type: "application/json"
          }
        ])

      render_upload(upload, "invalid.json")

      view
      |> form("#suite-form",
        suite: %{
          name: "Invalid Document Suite",
          prompt_id: prompt.id,
          test_cases: %{
            test_case_id => %{
              variable_values: %{name: "Alice"},
              assertions: %{
                assertion_type_0: "contains",
                assertion_value_0: "hello"
              }
            }
          }
        }
      )
      |> render_submit()

      {_path, flash} = assert_redirect(view)
      assert flash["error"] =~ "invalid.json (File content does not match type application/json)"
    end

    test "reuses document upload slots after removing test cases", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/suites/new")

      view
      |> element("[phx-click='add_test_case']")
      |> render_click()

      {first_test_case_id, first_upload_name} = first_document_upload(view)

      view
      |> element("[phx-click='remove_test_case'][phx-value-id='#{first_test_case_id}']")
      |> render_click()

      view
      |> element("[phx-click='add_test_case']")
      |> render_click()

      {_second_test_case_id, second_upload_name} = first_document_upload(view)

      assert second_upload_name == first_upload_name
    end

    test "creates suite with a deep compare assertion successfully", %{conn: conn} do
      prompt = prompt_fixture_with_version(%{template: "Hello {{name}}"})

      {:ok, view, _html} = live(conn, "/suites/new")

      view
      |> form("#suite-form", suite: %{name: "Deep Compare Suite", prompt_id: prompt.id})
      |> render_change()

      view
      |> element("[phx-click='add_test_case']")
      |> render_click()

      test_case_id = List.first(:sys.get_state(view.pid).socket.assigns.test_cases).id

      view
      |> render_click("add_assertion", %{"id" => test_case_id})

      view
      |> render_change("validate", %{
        "suite" => %{
          "name" => "Deep Compare Suite",
          "prompt_id" => prompt.id,
          "test_cases" => %{
            test_case_id => %{
              "variable_values" => %{
                "name" => "Alice"
              },
              "assertions" => %{
                "assertion_type_0" => "json_deep_compare"
              }
            }
          }
        }
      })

      view
      |> form("#suite-form",
        suite: %{
          name: "Deep Compare Suite",
          prompt_id: prompt.id,
          test_cases: %{
            test_case_id => %{
              variable_values: %{
                name: "Alice"
              },
              assertions: %{
                assertion_type_0: "json_deep_compare",
                assertion_expected_json_0: ~s({"status":"ok","count":2}),
                assertion_threshold_0: "75.0"
              }
            }
          }
        }
      )
      |> render_submit(%{
        "suite" => %{
          "name" => "Deep Compare Suite",
          "prompt_id" => prompt.id,
          "test_cases" => %{
            test_case_id => %{
              "variable_values" => %{
                "name" => "Alice"
              },
              "assertions" => %{
                "assertion_type_0" => "json_deep_compare",
                "assertion_expected_json_0" => ~s({"status":"ok","count":2}),
                "assertion_threshold_0" => "75.0"
              }
            }
          }
        }
      })

      {_path, flash} = assert_redirect(view)
      assert flash["info"] == "Suite created successfully"
    end

    test "creates a suite with typed json_field assertions after toggling from JSON to visual",
         %{conn: conn} do
      prompt = prompt_fixture_with_version(%{template: "Hello {{name}}"})

      {:ok, view, _html} = live(conn, "/suites/new")

      view
      |> form("#suite-form", suite: %{name: "Typed JSON Field Suite", prompt_id: prompt.id})
      |> render_change()

      view
      |> element("[phx-click='add_test_case']")
      |> render_click()

      test_case_id = List.first(:sys.get_state(view.pid).socket.assigns.test_cases).id

      view
      |> render_click("toggle_assertion_mode", %{"id" => test_case_id})

      view
      |> render_change("validate", %{
        "suite" => %{
          "name" => "Typed JSON Field Suite",
          "prompt_id" => prompt.id,
          "test_cases" => %{
            test_case_id => %{
              "variable_values" => %{"name" => "Alice"},
              "assertions_json" => ~s([{"type":"json_field","field":"count","expected":1}])
            }
          }
        }
      })

      view
      |> render_click("toggle_assertion_mode", %{"id" => test_case_id})

      assert has_element?(view, "#test_case_#{test_case_id}_assertion_expected_0[value='1']")

      view
      |> form("#suite-form",
        suite: %{
          name: "Typed JSON Field Suite",
          prompt_id: prompt.id,
          test_cases: %{
            test_case_id => %{
              variable_values: %{
                name: "Alice"
              },
              assertions: %{
                assertion_type_0: "json_field",
                assertion_field_0: "count",
                assertion_expected_0: "1",
                assertion_expected_json_value_0: "1"
              }
            }
          }
        }
      )
      |> render_submit(%{
        "suite" => %{
          "name" => "Typed JSON Field Suite",
          "prompt_id" => prompt.id,
          "test_cases" => %{
            test_case_id => %{
              "variable_values" => %{"name" => "Alice"},
              "assertions" => %{
                "assertion_type_0" => "json_field",
                "assertion_field_0" => "count",
                "assertion_expected_0" => "1",
                "assertion_expected_json_value_0" => "1"
              }
            }
          }
        }
      })

      {path, flash} = assert_redirect(view)
      assert flash["info"] == "Suite created successfully"

      [_, suite_id] = Regex.run(~r{/suites/([^/]+)$}, path)
      suite = Evals.get_suite_with_test_cases!(suite_id)
      [created_test_case] = suite.test_cases

      assert created_test_case.assertions == [
               %{"type" => "json_field", "field" => "count", "expected" => 1}
             ]
    end

    test "shows validation errors on invalid suite", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/suites/new")

      view
      |> form("#suite-form", suite: %{name: "", prompt_id: ""})
      |> render_submit(%{
        "suite" => %{
          "name" => "",
          "prompt_id" => ""
        }
      })

      assert has_element?(view, "p.text-error", "can't be blank")
    end

    test "validates JSON assertions", %{conn: conn} do
      prompt = prompt_fixture_with_version()

      {:ok, view, _html} = live(conn, "/suites/new")

      view
      |> form("#suite-form", suite: %{name: "", prompt_id: prompt.id})
      |> render_change()

      view
      |> element("[phx-click='add_test_case']")
      |> render_click()

      test_case_id = List.first(:sys.get_state(view.pid).socket.assigns.test_cases).id

      view
      |> render_click("toggle_assertion_mode", %{"id" => test_case_id})

      view
      |> form("#suite-form",
        suite: %{
          name: "Test Suite",
          prompt_id: prompt.id,
          test_cases: %{
            test_case_id => %{
              assertions_json: "{invalid json}"
            }
          }
        }
      )
      |> render_submit(%{
        "suite" => %{
          "name" => "Test Suite",
          "prompt_id" => prompt.id,
          "test_cases" => %{
            test_case_id => %{
              "assertions_json" => "{invalid json}"
            }
          }
        }
      })

      assert has_element?(view, "#flash-error", "Invalid JSON")
    end

    test "rejects invalid assertion types in JSON", %{conn: conn} do
      prompt = prompt_fixture_with_version()

      {:ok, view, _html} = live(conn, "/suites/new")

      view
      |> form("#suite-form", suite: %{name: "", prompt_id: prompt.id})
      |> render_change()

      view
      |> element("[phx-click='add_test_case']")
      |> render_click()

      test_case_id = List.first(:sys.get_state(view.pid).socket.assigns.test_cases).id

      view
      |> render_click("toggle_assertion_mode", %{"id" => test_case_id})

      view
      |> form("#suite-form",
        suite: %{
          name: "Test Suite",
          prompt_id: prompt.id,
          test_cases: %{
            test_case_id => %{
              assertions_json: ~s([{"type": "invalid_type", "value": "test"}])
            }
          }
        }
      )
      |> render_submit(%{
        "suite" => %{
          "name" => "Test Suite",
          "prompt_id" => prompt.id,
          "test_cases" => %{
            test_case_id => %{
              "assertions_json" => ~s([{"type": "invalid_type", "value": "test"}])
            }
          }
        }
      })

      assert has_element?(view, "#flash-error", "Invalid assertion type")
    end

    test "rejects blank assertion values in visual mode", %{conn: conn} do
      prompt = prompt_fixture_with_version(%{template: "Hello {{name}}"})

      {:ok, view, _html} = live(conn, "/suites/new")

      view
      |> form("#suite-form", suite: %{name: "", prompt_id: prompt.id})
      |> render_change()

      view
      |> element("[phx-click='add_test_case']")
      |> render_click()

      test_case_id = List.first(:sys.get_state(view.pid).socket.assigns.test_cases).id

      view
      |> render_click("add_assertion", %{"id" => test_case_id})

      view
      |> form("#suite-form",
        suite: %{
          "name" => "Test Suite",
          "prompt_id" => prompt.id,
          "test_cases" => %{
            test_case_id => %{
              "variable_values" => %{"name" => "Alice"},
              "assertions" => %{
                "assertion_type_0" => "contains",
                "assertion_value_0" => "   "
              }
            }
          }
        }
      )
      |> render_submit()

      assert has_element?(view, "#flash-error", "non-blank 'value' field")
    end

    test "uses nested variable inputs after prompt selection", %{conn: conn} do
      prompt = prompt_fixture_with_version(%{template: "Hello {{name}}"})

      {:ok, view, _html} = live(conn, "/suites/new")

      view
      |> form("#suite-form", suite: %{name: "", prompt_id: prompt.id})
      |> render_change()

      view
      |> element("[phx-click='add_test_case']")
      |> render_click()

      test_case_id = List.first(:sys.get_state(view.pid).socket.assigns.test_cases).id

      assert has_element?(view, "#test_case_#{test_case_id}_var_name")
    end

    test "changing prompt preserves other form fields", %{conn: conn} do
      prompt = prompt_fixture_with_version(%{template: "Hello {{name}}"})

      {:ok, view, _html} = live(conn, "/suites/new")

      view
      |> form("#suite-form", suite: %{name: "Suite Draft", prompt_id: prompt.id})
      |> render_change()

      assert has_element?(view, "#suite_name[value='Suite Draft']")
      assert has_element?(view, "#suite_prompt_id-select [data-select-value]", prompt.name)
    end
  end

  defp first_document_upload(view) do
    html = render(view)

    [_, test_case_id] = Regex.run(~r/id="test_case_([^"]+)_documents"/, html)
    [_, upload_name] = Regex.run(~r/type="file" name="(test_case_documents_\d+)"/, html)

    {test_case_id, String.to_existing_atom(upload_name)}
  end
end
