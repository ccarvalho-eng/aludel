defmodule Aludel.StorageTest do
  use ExUnit.Case, async: false

  import Mox

  alias Aludel.Evals.TestCaseDocument
  alias Aludel.Interfaces.Storage.Adapters.Local
  alias Aludel.Interfaces.StorageMock
  alias Aludel.Storage
  alias Aludel.Storage.Config

  setup :set_mox_from_context
  setup :verify_on_exit!

  test "get/2 fails fast for unknown backends" do
    assert {:error, :unknown_storage_backend} =
             Storage.get("test_case_documents/doc/test.txt",
               storage_backend: "Elixir.Aludel.Interfaces.Storage.Adapters.Unknown"
             )
  end

  test "delete/2 fails fast for unknown backends" do
    assert {:error, :unknown_storage_backend} =
             Storage.delete("test_case_documents/doc/test.txt",
               storage_backend: "Elixir.Aludel.Interfaces.Storage.Adapters.Unknown"
             )
  end

  test "get/2 rejects modules that are not storage adapters" do
    assert {:error, :unknown_storage_backend} =
             Storage.get("test_case_documents/doc/test.txt", storage_backend: "Elixir.String")
  end

  test "read/1 returns an error when storage metadata is missing" do
    assert {:error, :missing_document_data} = Storage.read(%TestCaseDocument{})
  end

  test "storage_key/2 normalizes dot-only filenames" do
    assert Storage.storage_key("doc-id", "..") == "test_case_documents/doc-id/unnamed_file"
    assert Storage.storage_key("doc-id", ".") == "test_case_documents/doc-id/unnamed_file"
  end

  test "read/1 uses backend-specific config for the persisted adapter" do
    configure_storage(
      adapter: Local,
      root: "/tmp/local-storage",
      backends: [
        {StorageMock, [bucket: "documents-bucket", region: "us-east-1"]}
      ]
    )

    expect(StorageMock, :get, fn "test_case_documents/doc/test.txt", config ->
      assert config[:bucket] == "documents-bucket"
      assert config[:region] == "us-east-1"
      refute Keyword.has_key?(config, :backends)
      {:ok, "payload"}
    end)

    assert {:ok, "payload"} =
             Storage.read(%TestCaseDocument{
               storage_key: "test_case_documents/doc/test.txt",
               storage_backend: Atom.to_string(StorageMock)
             })
  end

  test "get/2 ignores invalid config overrides" do
    configure_storage(
      adapter: Local,
      backends: [{StorageMock, [bucket: "documents-bucket"]}]
    )

    expect(StorageMock, :get, fn "test_case_documents/doc/test.txt", config ->
      assert config[:bucket] == "documents-bucket"
      {:ok, "payload"}
    end)

    assert {:ok, "payload"} =
             Storage.get("test_case_documents/doc/test.txt",
               storage_backend: Atom.to_string(StorageMock),
               config: :invalid_override
             )
  end

  test "local path_for/2 expands keys under the configured root" do
    assert Local.path_for("nested/file.txt", root: "/tmp/aludel-storage-root") ==
             "/tmp/aludel-storage-root/nested/file.txt"
  end

  test "local path_for/2 rejects paths outside the configured root" do
    assert_raise ArgumentError, "invalid storage key path", fn ->
      Local.path_for("../escape.txt", root: "/tmp/aludel-storage-root")
    end
  end

  test "storage configuration resolves nested system values" do
    variable = "ALUDEL_STORAGE_TEST_VALUE"
    original_value = System.get_env(variable)
    original_config = Application.get_env(:aludel, Aludel.Storage, [])

    System.put_env(variable, "resolved")

    Application.put_env(:aludel, Aludel.Storage,
      root: {:system, variable},
      backends: %{Local => [bucket: {:system, variable}]}
    )

    on_exit(fn ->
      restore_system_value(variable, original_value)
      Application.put_env(:aludel, Aludel.Storage, original_config)
    end)

    assert Config.get() == [root: "resolved", backends: %{Local => [bucket: "resolved"]}]
    assert Storage.config() == Config.get()
  end

  defp configure_storage(config) do
    original_config = Application.get_env(:aludel, Aludel.Storage, [])
    Application.put_env(:aludel, Aludel.Storage, config)

    on_exit(fn ->
      Application.put_env(:aludel, Aludel.Storage, original_config)
    end)
  end

  defp restore_system_value(variable, nil) do
    System.delete_env(variable)
  end

  defp restore_system_value(variable, value) do
    System.put_env(variable, value)
  end
end
