defmodule Aludel.Evals.TestCaseTest do
  use Aludel.DataCase, async: true

  alias Aludel.Evals.TestCase
  alias Aludel.Evals.TestCaseDocument

  describe "changeset/2" do
    test "valid changeset with all fields" do
      suite = suite_fixture()

      changeset =
        TestCase.changeset(%TestCase{}, %{
          suite_id: suite.id,
          variable_values: %{"name" => "John"},
          assertions: [
            %{"type" => "contains", "value" => "Hello"},
            %{"type" => "not_contains", "value" => "Goodbye"},
            %{"type" => "regex", "value" => "^Hello"},
            %{"type" => "exact_match", "value" => "Hello World"}
          ]
        })

      assert changeset.valid?
    end

    test "valid changeset accepts json_deep_compare assertions" do
      suite = suite_fixture()

      changeset =
        TestCase.changeset(%TestCase{}, %{
          suite_id: suite.id,
          variable_values: %{"name" => "John"},
          assertions: [
            %{
              "type" => "json_deep_compare",
              "expected" => %{"name" => "John", "age" => 30},
              "threshold" => 50.0
            }
          ]
        })

      assert changeset.valid?
    end

    test "requires suite_id" do
      changeset =
        TestCase.changeset(%TestCase{}, %{
          variable_values: %{},
          assertions: []
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).suite_id
    end

    test "requires variable_values" do
      suite = suite_fixture()

      changeset =
        TestCase.changeset(%TestCase{}, %{
          suite_id: suite.id,
          assertions: []
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).variable_values
    end

    test "requires assertions" do
      suite = suite_fixture()

      changeset =
        TestCase.changeset(%TestCase{}, %{
          suite_id: suite.id,
          variable_values: %{}
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).assertions
    end

    test "rejects assertions with unsupported types" do
      suite = suite_fixture()

      changeset =
        TestCase.changeset(%TestCase{}, %{
          suite_id: suite.id,
          variable_values: %{"name" => "John"},
          assertions: [%{"type" => "invalid_type", "value" => "Hello"}]
        })

      refute changeset.valid?

      assert {"Invalid assertion type at index 1: \"invalid_type\". Must be one of: contains, not_contains, regex, exact_match, json_field, json_deep_compare",
              []} =
               changeset.errors[:assertions]
    end

    test "rejects assertions with blank string values" do
      suite = suite_fixture()

      changeset =
        TestCase.changeset(%TestCase{}, %{
          suite_id: suite.id,
          variable_values: %{"name" => "John"},
          assertions: [%{"type" => "contains", "value" => "   "}]
        })

      refute changeset.valid?

      assert {"Assertion at index 1: contains type requires a non-blank 'value' field", []} =
               changeset.errors[:assertions]
    end

    test "accepts multi-turn messages and metadata" do
      suite = suite_fixture()

      changeset =
        TestCase.changeset(%TestCase{}, %{
          suite_id: suite.id,
          variable_values: %{},
          messages: [
            %{"role" => "user", "content" => "Hello"},
            %{"role" => "assistant", "content" => "Hi"},
            %{"role" => "user", "content" => "Can you help?"}
          ],
          assertions: [],
          metadata: %{"segment" => "support"}
        })

      assert changeset.valid?
    end

    test "rejects invalid messages and non-JSON metadata" do
      suite = suite_fixture()

      changeset =
        TestCase.changeset(%TestCase{}, %{
          suite_id: suite.id,
          variable_values: %{},
          messages: [%{"role" => "assistant", "content" => "No user turn"}],
          assertions: [],
          metadata: %{"pid" => self()}
        })

      refute changeset.valid?
      assert "must end with a user turn" in errors_on(changeset).messages
      assert "must be JSON-encodable" in errors_on(changeset).metadata
    end
  end

  describe "associations" do
    test "has_many documents" do
      test_case = test_case_fixture()

      {:ok, doc} =
        %TestCaseDocument{}
        |> TestCaseDocument.changeset(%{
          test_case_id: test_case.id,
          filename: "test.pdf",
          content_type: "application/pdf",
          size_bytes: 100,
          storage_key: "test_case_documents/test-case/test.pdf",
          storage_backend: "local"
        })
        |> Repo.insert()

      loaded = Repo.preload(test_case, :documents)

      assert [
               %TestCaseDocument{
                 id: doc_id,
                 storage_key: storage_key,
                 storage_backend: storage_backend
               }
             ] = loaded.documents

      assert doc_id == doc.id
      assert storage_key == doc.storage_key
      assert storage_backend == doc.storage_backend
    end
  end
end
