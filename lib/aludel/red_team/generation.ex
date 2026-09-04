defmodule Aludel.RedTeam.Generation do
  @moduledoc """
  The review boundary returned by `Aludel.RedTeam.generate/2`.

  A generation records validated candidates, sanitized per-category failures,
  observed usage, and the limits applied to the model calls. Creating this
  value does not persist dataset entries.
  """

  alias Aludel.RedTeam.GeneratedCase

  @enforce_keys [
    :id,
    :schema_version,
    :prompt_version,
    :status,
    :provider,
    :requested_categories,
    :cases,
    :failures,
    :usage,
    :limits,
    :target_context_checksum,
    :generated_at,
    :checksum
  ]

  defstruct @enforce_keys

  @type status :: :completed | :partial_failure | :failed
  @type provider :: %{id: String.t(), type: String.t(), model: String.t()}
  @type failure :: %{
          category: Aludel.RedTeam.Catalog.category(),
          type: :provider_error | :timeout | :invalid_response | :budget_exhausted,
          message: String.t()
        }
  @type usage :: %{
          requests: non_neg_integer(),
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          total_tokens: non_neg_integer(),
          cost_usd: number()
        }
  @type limits :: %{
          cases_per_category: pos_integer(),
          max_requests: pos_integer(),
          max_output_tokens: pos_integer(),
          max_total_tokens: pos_integer(),
          max_cost_usd: number(),
          request_timeout_ms: pos_integer(),
          max_target_context_chars: pos_integer(),
          max_response_bytes: pos_integer()
        }

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          schema_version: pos_integer(),
          prompt_version: pos_integer(),
          status: status(),
          provider: provider(),
          requested_categories: [Aludel.RedTeam.Catalog.category()],
          cases: [GeneratedCase.t()],
          failures: [failure()],
          usage: usage(),
          limits: limits(),
          target_context_checksum: String.t(),
          generated_at: DateTime.t(),
          checksum: String.t()
        }
end
