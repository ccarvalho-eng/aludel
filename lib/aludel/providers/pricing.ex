defmodule Aludel.Providers.Pricing do
  @moduledoc """
  Resolves pricing for a given provider and model.

  Uses LLMDB's per-model cost data as the default source of truth,
  with support for user-defined custom pricing overrides.

  Rates are always expressed per 1 million tokens.

  LLMDB model data is indexed once into `:persistent_term` on first use,
  making all subsequent lookups O(1).
  """

  @persistent_term_key {__MODULE__, :index}

  @doc """
  Returns the effective pricing for a provider/model combination.

  ## Priority

  1. If `custom_pricing` is a map with `input` and `output` keys, return it directly
  2. Ollama models always resolve to free (`%{input: 0.0, output: 0.0}`) since they
     run locally and use a different provider atom in LLMDB (`:ollama_cloud`)
  3. LLMDB index (built once from `LLMDB.models()`, cached in `:persistent_term`) — O(1) lookup
  4. Returns `nil` if no pricing data is available

  ## Parameters

    - `provider` - Provider atom (e.g., `:openai`, `:anthropic`)
    - `model` - Model ID string (e.g., `"gpt-4o"`)
    - `custom_pricing` - Optional map with `:input`/`:output` or `"input"`/`"output"` keys

  ## Returns

    - `%{input: float, output: float}` with rates per 1M tokens
    - `nil` if no pricing data is available
  """
  @spec get_pricing(atom(), String.t(), map() | nil) :: %{input: number(), output: number()} | nil
  def get_pricing(provider, model, custom_pricing \\ nil)

  def get_pricing(_provider, _model, %{input: input, output: output})
      when is_number(input) and is_number(output) do
    %{input: input, output: output}
  end

  def get_pricing(_provider, _model, %{"input" => input, "output" => output})
      when is_number(input) and is_number(output) do
    %{input: input, output: output}
  end

  def get_pricing(:ollama, _model, _custom_pricing) do
    %{input: 0.0, output: 0.0}
  end

  def get_pricing(provider, model, _custom_pricing) do
    Map.get(llmdb_index(), {provider, model})
  end

  @doc """
  Normalizes string-keyed or atom-keyed pricing into the internal atom-keyed shape.

  String keys take precedence because persisted JSON maps use strings. Missing or
  false string values fall back to their atom-keyed counterparts for compatibility
  with programmatically constructed providers.
  """
  @spec normalize(map()) :: %{input: term(), output: term()}
  def normalize(pricing) when is_map(pricing) do
    %{
      input: pricing_value(pricing, :input),
      output: pricing_value(pricing, :output)
    }
  end

  @doc """
  Formats pricing for human-readable display.

  ## Examples

      iex> Aludel.Providers.Pricing.format_pricing(%{input: 3.0, output: 15.0})
      "$3.00 / $15.00 per 1M tokens"

      iex> Aludel.Providers.Pricing.format_pricing(%{input: 0, output: 0})
      "Free"

      iex> Aludel.Providers.Pricing.format_pricing(nil)
      "Unknown"
  """
  @spec format_pricing(%{input: number(), output: number()} | nil) :: String.t()
  def format_pricing(nil), do: "Unknown"

  def format_pricing(%{input: input, output: output})
      when is_number(input) and is_number(output) do
    if input == 0 and output == 0 do
      "Free"
    else
      "$#{format_rate(input)} / $#{format_rate(output)} per 1M tokens"
    end
  end

  defp llmdb_index do
    case :persistent_term.get(@persistent_term_key, nil) do
      nil -> build_and_cache_index()
      index -> index
    end
  end

  defp pricing_value(pricing, key) do
    case Map.fetch(pricing, Atom.to_string(key)) do
      {:ok, value} when value not in [nil, false] -> value
      _other -> Map.get(pricing, key)
    end
  end

  defp build_and_cache_index do
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    models = apply(LLMDB, :models, [])

    index =
      Enum.reduce(models, %{}, fn
        %{provider: p, id: id, cost: %{input: inp, output: out}}, acc
        when is_number(inp) and is_number(out) ->
          Map.put(acc, {p, id}, %{input: inp, output: out})

        _, acc ->
          acc
      end)

    if map_size(index) > 0 do
      :persistent_term.put(@persistent_term_key, index)
    end

    index
  end

  defp format_rate(rate) when is_number(rate) do
    :erlang.float_to_binary(rate / 1, decimals: 2)
  end
end
