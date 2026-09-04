defmodule Aludel.Evals.AssertionParserTest do
  use ExUnit.Case, async: true

  alias Aludel.Evals.AssertionParser

  describe "parse/2" do
    test "parses JSON assertions" do
      params = %{
        "assertions_json" => ~s([{"type":"contains","value":"hello"}])
      }

      assert {:ok, [%{"type" => "contains", "value" => "hello"}]} =
               AssertionParser.parse(:json, params)
    end

    test "rejects invalid JSON assertions" do
      params = %{"assertions_json" => "{invalid json}"}

      assert {:error, "Invalid JSON syntax in assertions"} =
               AssertionParser.parse(:json, params)
    end

    test "rejects JSON assertions when the payload is not a list" do
      params = %{"assertions_json" => ~s({"type":"contains","value":"hello"})}

      assert {:error, "Invalid JSON: assertions must be a list"} =
               AssertionParser.parse(:json, params)
    end

    test "rejects JSON assertions with an invalid type" do
      params = %{
        "assertions_json" => ~s([{"type":"invalid_type","value":"hello"}])
      }

      assert {:error, message} = AssertionParser.parse(:json, params)
      assert message =~ "Invalid assertion type at index 1"
    end

    test "rejects JSON string assertions with blank values" do
      params = %{
        "assertions_json" => ~s([{"type":"contains","value":"   "}])
      }

      assert {:error, message} = AssertionParser.parse(:json, params)
      assert message =~ "contains type requires a non-blank 'value' field"
    end

    test "parses visual assertions" do
      params = %{
        "assertions" => %{
          "assertion_type_0" => "contains",
          "assertion_value_0" => "hello",
          "assertion_type_1" => "json_field",
          "assertion_field_1" => "sentiment",
          "assertion_expected_1" => "positive"
        }
      }

      assert {:ok,
              [
                %{"type" => "contains", "value" => "hello"},
                %{
                  "type" => "json_field",
                  "field" => "sentiment",
                  "expected" => "positive"
                }
              ]} = AssertionParser.parse(:visual, params)
    end

    test "parses json_deep_compare assertions in JSON mode" do
      params = %{
        "assertions_json" =>
          ~s([{"type":"json_deep_compare","expected":{"status":"ok","count":2},"threshold":75.0}])
      }

      assert {:ok,
              [
                %{
                  "type" => "json_deep_compare",
                  "expected" => %{"status" => "ok", "count" => 2},
                  "threshold" => 75.0
                }
              ]} = AssertionParser.parse(:json, params)
    end

    test "parses rubric judge assertions in JSON mode" do
      provider_id = Ecto.UUID.generate()

      params = %{
        "assertions_json" =>
          Jason.encode!([
            %{
              "type" => "rubric_judge",
              "rubric" => "The answer must be correct.",
              "provider_id" => provider_id,
              "threshold" => 85,
              "expected" => "Reference answer"
            }
          ])
      }

      assert {:ok, [assertion]} = AssertionParser.parse(:json, params)
      assert assertion["type"] == "rubric_judge"
      assert assertion["provider_id"] == provider_id
      assert assertion["threshold"] == 85
    end

    test "rejects incomplete rubric judge assertions" do
      params = %{
        "assertions_json" => ~s([{"type":"rubric_judge","rubric":" ","provider_id":"bad"}])
      }

      assert {:error, message} = AssertionParser.parse(:json, params)
      assert message =~ "rubric_judge type requires a non-blank 'rubric'"
    end

    test "parses json_deep_compare assertions in visual mode" do
      params = %{
        "assertions" => %{
          "assertion_type_0" => "json_deep_compare",
          "assertion_expected_json_0" => ~s({"status":"ok","count":2}),
          "assertion_threshold_0" => "75.0"
        }
      }

      assert {:ok,
              [
                %{
                  "type" => "json_deep_compare",
                  "expected" => %{"status" => "ok", "count" => 2},
                  "threshold" => 75.0
                }
              ]} = AssertionParser.parse(:visual, params)
    end

    test "rejects visual assertions with invalid indices" do
      params = %{
        "assertions" => %{
          "assertion_type_abc" => "contains",
          "assertion_value_abc" => "hello"
        }
      }

      assert {:error, "Invalid assertion index: abc"} =
               AssertionParser.parse(:visual, params)
    end

    test "rejects visual string assertions with blank values" do
      params = %{
        "assertions" => %{
          "assertion_type_0" => "contains",
          "assertion_value_0" => "  "
        }
      }

      assert {:error, message} = AssertionParser.parse(:visual, params)
      assert message =~ "contains type requires a non-blank 'value' field"
    end

    test "rejects json_field assertions missing expected keys" do
      params = %{
        "assertions_json" => ~s([{"type":"json_field"}])
      }

      assert {:error, message} = AssertionParser.parse(:json, params)
      assert message =~ "json_field type requires 'field' and 'expected' fields"
    end

    test "rejects json_field assertions with blank field values" do
      params = %{
        "assertions_json" => ~s([{"type":"json_field","field":"   ","expected":"positive"}])
      }

      assert {:error, message} = AssertionParser.parse(:json, params)
      assert message =~ "json_field type requires a non-blank 'field' value"
    end

    test "rejects json_field assertions with blank expected values in JSON mode" do
      params = %{
        "assertions_json" => ~s([{"type":"json_field","field":"sentiment","expected":"   "}])
      }

      assert {:error, message} = AssertionParser.parse(:json, params)
      assert message =~ "json_field type requires a non-blank 'expected' value"
    end

    test "rejects json_field assertions with blank expected values in visual mode" do
      params = %{
        "assertions" => %{
          "assertion_type_0" => "json_field",
          "assertion_field_0" => "sentiment",
          "assertion_expected_0" => "  "
        }
      }

      assert {:error, message} = AssertionParser.parse(:visual, params)
      assert message =~ "json_field type requires a non-blank 'expected' value"
    end

    test "rejects json_deep_compare assertions with invalid expected JSON" do
      params = %{
        "assertions_json" =>
          ~s([{"type":"json_deep_compare","expected":"not-json-object","threshold":75.0}])
      }

      assert {:error, message} = AssertionParser.parse(:json, params)
      assert message =~ "json_deep_compare type requires an 'expected' map or list"
    end

    test "rejects json_deep_compare assertions with invalid thresholds" do
      params = %{
        "assertions_json" =>
          ~s([{"type":"json_deep_compare","expected":{"status":"ok"},"threshold":120}])
      }

      assert {:error, message} = AssertionParser.parse(:json, params)
      assert message =~ "json_deep_compare type requires a threshold between 0 and 100"
    end
  end

  describe "build_form_params/1" do
    test "builds JSON and visual params from assertions" do
      assertions = [%{"type" => "contains", "value" => "hello"}]

      assert %{
               "assertions_json" => assertions_json,
               "assertions" => %{
                 "assertion_type_0" => "contains",
                 "assertion_value_0" => "hello"
               }
             } = AssertionParser.build_form_params(assertions)

      assert assertions_json =~ "\"type\": \"contains\""
    end

    test "builds visual params for typed json_field assertions" do
      assertions = [%{"type" => "json_field", "field" => "count", "expected" => 1}]

      assert %{
               "assertions" => %{
                 "assertion_type_0" => "json_field",
                 "assertion_field_0" => "count",
                 "assertion_expected_0" => "1",
                 "assertion_expected_json_value_0" => expected_json
               }
             } = AssertionParser.build_form_params(assertions)

      assert expected_json == "1"
    end

    test "builds visual params for json_deep_compare assertions" do
      assertions = [
        %{
          "type" => "json_deep_compare",
          "expected" => %{"status" => "ok", "count" => 2},
          "threshold" => 75.0
        }
      ]

      assert %{
               "assertions_json" => assertions_json,
               "assertions" => %{
                 "assertion_type_0" => "json_deep_compare",
                 "assertion_expected_json_0" => expected_json,
                 "assertion_threshold_0" => "75.0"
               }
             } = AssertionParser.build_form_params(assertions)

      assert assertions_json =~ "\"type\": \"json_deep_compare\""
      assert expected_json =~ "\"status\": \"ok\""
    end
  end

  describe "preview_visual/1" do
    test "keeps json_field assertions in draft mode when required inputs are blank" do
      params = %{
        "assertions" => %{
          "assertion_type_0" => "json_field",
          "assertion_field_0" => "",
          "assertion_expected_0" => ""
        }
      }

      assert {:ok,
              [
                %{
                  "type" => "json_field",
                  "field" => "",
                  "expected" => ""
                }
              ]} = AssertionParser.preview_visual(params)
    end

    test "switches away from deep compare inputs in draft mode" do
      params = %{
        "assertions" => %{
          "assertion_type_0" => "json_field",
          "assertion_field_0" => "status",
          "assertion_expected_0" => "ok",
          "assertion_expected_json_0" => ~s({"status":"ok"}),
          "assertion_threshold_0" => "80.0"
        }
      }

      assert {:ok,
              [
                %{
                  "type" => "json_field",
                  "field" => "status",
                  "expected" => "ok"
                }
              ]} = AssertionParser.preview_visual(params)
    end

    test "preserves typed json_field expected values when the visual field is unchanged" do
      params = %{
        "assertions" => %{
          "assertion_type_0" => "json_field",
          "assertion_field_0" => "count",
          "assertion_expected_0" => "1",
          "assertion_expected_json_value_0" => "1"
        }
      }

      assert {:ok, [%{"type" => "json_field", "field" => "count", "expected" => 1}]} =
               AssertionParser.parse(:visual, params)
    end
  end
end
