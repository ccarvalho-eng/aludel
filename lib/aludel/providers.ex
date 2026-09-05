defmodule Aludel.Providers do
  @moduledoc """
  Context for managing AI provider configurations.
  """

  alias Aludel.Providers.Pricing
  alias Aludel.Providers.Provider
  alias Ecto.Changeset

  @doc """
  Lists all providers in the system.
  """
  @spec list_providers() :: [Provider.t()]
  def list_providers do
    repo().all(Provider)
  end

  @doc """
  Gets a provider by ID, raising if not found.
  """
  @spec get_provider!(binary()) :: Provider.t()
  def get_provider!(id) do
    repo().get!(Provider, id)
  end

  @doc """
  Gets a provider by ID, returning `nil` when it does not exist.
  """
  @spec get_provider(binary()) :: Provider.t() | nil
  def get_provider(id) do
    repo().get(Provider, id)
  end

  @doc """
  Creates a new provider.
  """
  @spec create_provider(map()) ::
          {:ok, Provider.t()} | {:error, Changeset.t()}
  def create_provider(attrs \\ %{}) do
    %Provider{}
    |> Provider.changeset(attrs)
    |> repo().insert()
  end

  @doc """
  Updates an existing provider.
  """
  @spec update_provider(Provider.t(), map()) ::
          {:ok, Provider.t()} | {:error, Changeset.t()}
  def update_provider(%Provider{} = provider, attrs) do
    provider
    |> Provider.changeset(attrs)
    |> repo().update()
  end

  @doc """
  Deletes a provider.
  """
  @spec delete_provider(Provider.t()) ::
          {:ok, Provider.t()} | {:error, Changeset.t()}
  def delete_provider(%Provider{} = provider) do
    repo().delete(provider)
  end

  @doc """
  Returns a changeset for tracking provider changes.
  """
  @spec change_provider(Provider.t(), map()) :: Changeset.t()
  def change_provider(%Provider{} = provider, attrs \\ %{}) do
    Provider.changeset(provider, attrs)
  end

  @doc """
  Fetches available models for a given provider type.
  """
  @spec fetch_models(nil | binary() | atom()) :: [map()]
  def fetch_models(nil), do: []
  def fetch_models(""), do: []

  def fetch_models(provider_type) when is_binary(provider_type) do
    fetch_model_groups(provider_type).active
  end

  def fetch_models(provider_type) when is_atom(provider_type) do
    fetch_model_groups(provider_type).active
  end

  @doc """
  Fetches models grouped into active and deprecated sets.
  """
  @spec fetch_model_groups(nil | binary() | atom()) :: %{
          active: [map()],
          deprecated: [map()]
        }
  def fetch_model_groups(nil), do: %{active: [], deprecated: []}
  def fetch_model_groups(""), do: %{active: [], deprecated: []}

  def fetch_model_groups(provider_type) when is_binary(provider_type) do
    case provider_type do
      "openai" -> fetch_model_groups(:openai)
      "anthropic" -> fetch_model_groups(:anthropic)
      "ollama" -> fetch_model_groups(:ollama)
      "google" -> fetch_model_groups(:google)
      "xai" -> fetch_model_groups(:xai)
      "groq" -> fetch_model_groups(:groq)
      "openrouter" -> fetch_model_groups(:openrouter)
      _ -> %{active: [], deprecated: []}
    end
  end

  def fetch_model_groups(provider_type) when is_atom(provider_type) do
    # credo:disable-for-lines:2 Credo.Check.Refactor.Apply
    LLMDB
    |> apply(:models, [provider_type])
    |> Enum.filter(&text_generation_model?/1)
    |> Enum.map(&normalize_model/1)
    |> group_models()
  rescue
    _ -> %{active: [], deprecated: []}
  end

  @doc false
  @spec text_generation_model?(map()) :: boolean()
  def text_generation_model?(%{capabilities: %{chat: true}}) do
    true
  end

  def text_generation_model?(%{modalities: %{input: input, output: output}})
      when is_list(input) and is_list(output) do
    :text in input and :text in output
  end

  def text_generation_model?(_model) do
    false
  end

  @doc false
  @spec group_models([map()]) :: %{active: [map()], deprecated: [map()]}
  def group_models(models) when is_list(models) do
    models
    |> Enum.sort_by(fn %{name: name, id: id} ->
      {String.downcase(name), String.downcase(id)}
    end)
    |> Enum.group_by(& &1.deprecated)
    |> then(fn grouped ->
      %{active: Map.get(grouped, false, []), deprecated: Map.get(grouped, true, [])}
    end)
  end

  @doc """
  Resolves the LLMDB default pricing for a given provider atom and model string.

  Returns `nil` when either argument is nil/empty or when no pricing data is found.
  """
  @spec default_pricing(atom() | binary() | nil, String.t() | nil) ::
          %{input: float(), output: float()} | nil
  def default_pricing(nil, _model), do: nil
  def default_pricing(_provider, nil), do: nil
  def default_pricing(_provider, ""), do: nil

  def default_pricing(provider, model) when is_atom(provider) and is_binary(model) do
    Pricing.get_pricing(provider, model)
  end

  def default_pricing(provider, model) when is_binary(provider) and is_binary(model) do
    default_pricing(to_provider_atom(provider), model)
  end

  @doc """
  Builds the `"pricing"` key in a params map from raw form string inputs.

  When `custom_pricing_enabled` is `true`, parses `"pricing_input"` and
  `"pricing_output"` from `params` into numeric rates and sets `"pricing"`.
  Invalid strings are forwarded as-is so changeset validation surfaces the
  error. When disabled, `"pricing"` is set to `nil`.
  """
  @spec build_pricing_attrs(map(), boolean()) :: map()
  def build_pricing_attrs(params, true) do
    input = parse_pricing_value(params["pricing_input"])
    output = parse_pricing_value(params["pricing_output"])

    case {input, output} do
      {:invalid, _} ->
        Map.put(params, "pricing", %{
          "input" => params["pricing_input"],
          "output" => params["pricing_output"]
        })

      {_, :invalid} ->
        Map.put(params, "pricing", %{
          "input" => params["pricing_input"],
          "output" => params["pricing_output"]
        })

      {i, o} when is_number(i) and is_number(o) ->
        Map.put(params, "pricing", %{"input" => i, "output" => o})

      {nil, nil} ->
        Map.put(params, "pricing", nil)

      _ ->
        Map.put(params, "pricing", %{
          "input" => params["pricing_input"],
          "output" => params["pricing_output"]
        })
    end
  end

  def build_pricing_attrs(params, _custom_pricing_disabled) do
    Map.put(params, "pricing", nil)
  end

  @doc """
  Extracts pricing-related virtual field values from a persisted provider.

  Returns a map suitable for merging into changeset attrs or socket assigns
  when re-hydrating the provider form on edit.
  """
  @spec pricing_form_attrs(Provider.t()) :: %{
          custom_pricing_enabled: boolean(),
          pricing_input: String.t(),
          pricing_output: String.t()
        }
  def pricing_form_attrs(%Provider{pricing: pricing}) do
    has_custom = is_map(pricing) and map_size(pricing) > 0

    {input, output} =
      if has_custom do
        %{input: i, output: o} = Pricing.normalize(pricing)
        {to_string(i), to_string(o)}
      else
        {"", ""}
      end

    %{
      custom_pricing_enabled: has_custom,
      pricing_input: input,
      pricing_output: output
    }
  end

  defp parse_pricing_value(nil), do: nil
  defp parse_pricing_value(""), do: nil

  defp parse_pricing_value(value) when is_binary(value) do
    case Float.parse(value) do
      {num, ""} -> num
      {_num, _remainder} -> :invalid
      :error -> :invalid
    end
  end

  defp to_provider_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end

  defp normalize_model(%{id: id} = model) do
    name =
      case Map.get(model, :name) do
        nil -> id
        "" -> id
        value -> value
      end

    %{id: id, name: name, deprecated: Map.get(model, :deprecated, false)}
  end

  defp repo, do: Aludel.Repo.get()
end
