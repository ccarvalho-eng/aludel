defmodule Aludel.Storage do
  @moduledoc """
  Domain-facing facade for document storage backends.

  Test case documents are persisted through the configured storage adapter.
  """

  alias Aludel.Evals.TestCaseDocument
  alias Aludel.Interfaces.Storage.Adapters.AWS
  alias Aludel.Interfaces.Storage.Adapters.GCS
  alias Aludel.Interfaces.Storage.Adapters.Local
  alias Aludel.Storage.Config

  @type config :: keyword()
  @type error_reason :: term()

  @default_adapter Local
  @backend_names %{
    Local => "local",
    AWS => "aws",
    GCS => "gcs"
  }
  @backend_modules Map.new(@backend_names, fn {module, backend_name} -> {backend_name, module} end)
  @storage_callbacks [put: 4, get: 2, delete: 2]

  @doc """
  Persists document contents through the configured adapter and returns the
  adapter-specific storage key to save with the document row.
  """
  @spec put(String.t(), binary(), String.t()) :: {:ok, String.t()} | {:error, error_reason()}
  def put(key, data, content_type) do
    adapter().put(key, data, content_type, config())
  end

  @doc """
  Reads a storage key through its owning backend.

  Use `:storage_backend` to select a named historical backend and `:config` to
  overlay adapter configuration for this operation.
  """
  @spec get(String.t(), keyword()) :: {:ok, binary()} | {:error, error_reason()}
  def get(key, opts \\ []) do
    with {:ok, storage_adapter} <- adapter_for(opts) do
      storage_adapter.get(key, config_for(storage_adapter, opts))
    end
  end

  @doc """
  Deletes a storage key through its owning backend.

  Accepts the same `:storage_backend` and `:config` options as `get/2`.
  """
  @spec delete(String.t(), keyword()) :: :ok | {:error, error_reason()}
  def delete(key, opts \\ []) do
    with {:ok, storage_adapter} <- adapter_for(opts) do
      storage_adapter.delete(key, config_for(storage_adapter, opts))
    end
  end

  @doc """
  Reads the contents associated with a test case document.

  The document's persisted backend name is honored, allowing records created
  before a backend switch to remain readable. Documents without storage
  metadata return `{:error, :missing_document_data}`.
  """
  @spec read(TestCaseDocument.t()) :: {:ok, binary()} | {:error, error_reason()}
  def read(%TestCaseDocument{storage_key: key, storage_backend: backend})
      when is_binary(key) and is_binary(backend) do
    get(key, storage_backend: backend)
  end

  def read(%TestCaseDocument{}), do: {:error, :missing_document_data}

  @doc """
  Returns the currently configured storage adapter.

  The local filesystem adapter is used when no adapter is configured.
  """
  @spec adapter() :: module()
  def adapter, do: Keyword.get(config(), :adapter, @default_adapter)

  @doc """
  Returns the resolved application storage configuration.
  """
  @spec config() :: config()
  def config do
    Config.get()
  end

  @doc """
  Returns the stable persisted name for a storage adapter.
  """
  @spec backend_name(module()) :: String.t()
  def backend_name(storage_adapter \\ adapter()) do
    Map.get(@backend_names, storage_adapter, Atom.to_string(storage_adapter))
  end

  @doc """
  Builds a namespaced storage key for an uploaded document.

  Directory components are removed from the filename and unsupported
  characters are replaced with underscores.
  """
  @spec storage_key(Ecto.UUID.t(), String.t()) :: String.t()
  def storage_key(document_id, filename) do
    Path.join(["test_case_documents", document_id, sanitize_filename(filename)])
  end

  @doc """
  Resolves a persisted backend name to a storage adapter module.

  `nil` selects the active adapter. Unknown names return
  `{:error, :unknown_storage_backend}` without creating atoms.
  """
  @spec resolve_backend(String.t() | nil) :: {:ok, module()} | {:error, :unknown_storage_backend}
  def resolve_backend(nil), do: {:ok, adapter()}

  def resolve_backend(backend) when is_binary(backend) do
    case Map.get(@backend_modules, backend) do
      nil ->
        resolve_dynamic_backend(backend)

      storage_adapter ->
        {:ok, storage_adapter}
    end
  end

  defp adapter_for(opts) do
    opts
    |> Keyword.get(:storage_backend)
    |> resolve_backend()
  end

  defp config_for(storage_adapter, opts) do
    base_config =
      config()
      |> Keyword.drop([:adapter, :backends])
      |> Keyword.merge(backend_config(storage_adapter))

    case Keyword.get(opts, :config) do
      nil -> base_config
      override when is_list(override) -> Keyword.merge(base_config, override)
      _override -> base_config
    end
  end

  defp backend_config(storage_adapter) do
    case Keyword.get(config(), :backends, []) do
      backends when is_list(backends) ->
        list_backend_config(backends, storage_adapter)

      backends when is_map(backends) ->
        Map.get(backends, storage_adapter) ||
          Map.get(backends, Atom.to_string(storage_adapter), [])

      _ ->
        []
    end
  end

  defp list_backend_config(backends, storage_adapter) do
    backend_name = Atom.to_string(storage_adapter)

    Enum.find_value(backends, [], fn
      {^storage_adapter, config} when is_list(config) -> config
      {^backend_name, config} when is_list(config) -> config
      _other -> nil
    end)
  end

  defp resolve_dynamic_backend(backend) do
    module = String.to_existing_atom(backend)

    if storage_adapter_module?(module) do
      {:ok, module}
    else
      {:error, :unknown_storage_backend}
    end
  rescue
    ArgumentError -> {:error, :unknown_storage_backend}
  end

  defp storage_adapter_module?(module) do
    Code.ensure_loaded?(module) and
      Enum.all?(@storage_callbacks, fn {name, arity} ->
        function_exported?(module, name, arity)
      end)
  end

  defp sanitize_filename(filename) do
    sanitized =
      filename
      |> Path.basename()
      |> String.replace(~r/[^a-zA-Z0-9._-]+/u, "_")

    if sanitized == "" or String.match?(sanitized, ~r/^\.+$/) do
      "unnamed_file"
    else
      sanitized
    end
  end
end
