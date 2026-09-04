defmodule Aludel.Evals.Metric.Context do
  @moduledoc """
  Evidence available to an evaluation metric.

  The context keeps metric implementations independent from Ecto schemas while
  providing enough information for deterministic checks, model-based judges,
  and application-defined evaluators. Optional fields use JSON-compatible
  values so results can be reproduced and reported consistently.

  Existing metrics that only need generated text may continue to accept a
  string. Use `new/2` when a metric needs prompt, provider, document, or
  execution evidence.
  """

  @enforce_keys [:output]
  defstruct output: nil,
            expected: nil,
            rendered_input: nil,
            prompt_template: nil,
            variables: %{},
            messages: [],
            documents: [],
            metadata: %{},
            provider: nil,
            prompt_version: nil,
            execution: %{}

  @type json_value ::
          nil
          | boolean()
          | number()
          | String.t()
          | [json_value()]
          | %{optional(String.t()) => json_value()}

  @type t :: %__MODULE__{
          output: String.t(),
          expected: json_value(),
          rendered_input: String.t() | nil,
          prompt_template: String.t() | nil,
          variables: map(),
          messages: [map()],
          documents: [map()],
          metadata: map(),
          provider: map() | nil,
          prompt_version: map() | nil,
          execution: map()
        }

  @doc """
  Creates a metric context for generated output and optional evidence.
  """
  @spec new(String.t(), keyword()) :: t()
  def new(output, attrs \\ [])

  def new(output, attrs) when is_binary(output) and is_list(attrs) do
    struct!(__MODULE__, Keyword.put(attrs, :output, output))
  end

  def new(_output, _attrs) do
    raise ArgumentError, "metric output must be a string"
  end
end
