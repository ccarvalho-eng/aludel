defmodule Aludel.Executor do
  @moduledoc """
  Behaviour and configuration helpers for execution mode dispatch.
  """

  @type prompt_version_input :: %{
          id: binary(),
          template: String.t(),
          version: integer()
        }

  @type provider_input :: %{
          id: binary(),
          provider: atom(),
          model: String.t(),
          config: map() | nil
        }

  @type document_input :: %{
          name: String.t(),
          content_type: String.t(),
          data: binary()
        }

  @type input :: %{
          kind: :run | :suite,
          prompt_version: prompt_version_input(),
          variables: map(),
          messages: [map()],
          documents: [document_input()],
          provider: provider_input() | nil,
          metadata: map() | nil
        }

  @type result :: %{
          output: String.t(),
          input_tokens: non_neg_integer() | nil,
          output_tokens: non_neg_integer() | nil,
          latency_ms: non_neg_integer() | nil,
          cost_usd: float() | nil,
          metadata: map() | nil
        }

  @callback run(input()) :: {:ok, result()} | {:error, term()}

  @spec execution_mode() :: term()
  def execution_mode do
    Application.get_env(:aludel, :execution_mode, :native)
  end

  @spec configured_execution_mode() ::
          {:ok, :native | :callback} | {:error, {:invalid_execution_mode, term()}}
  def configured_execution_mode do
    case execution_mode() do
      nil -> {:ok, :native}
      :native -> {:ok, :native}
      :callback -> {:ok, :callback}
      mode -> {:error, {:invalid_execution_mode, mode}}
    end
  end

  @spec execution_mode_label() :: String.t()
  def execution_mode_label do
    case configured_execution_mode() do
      {:ok, :callback} -> "App Callback"
      {:ok, :native} -> "Native"
      {:error, _reason} -> "Invalid Configuration"
    end
  end

  @spec configured_executor() :: {:ok, module()} | {:error, :executor_not_configured | term()}
  def configured_executor do
    case Application.get_env(:aludel, :executor) do
      nil ->
        {:error, :executor_not_configured}

      module when is_atom(module) ->
        if Code.ensure_loaded?(module) and function_exported?(module, :run, 1) do
          {:ok, module}
        else
          {:error, {:invalid_executor, module}}
        end

      other ->
        {:error, {:invalid_executor, other}}
    end
  end
end
