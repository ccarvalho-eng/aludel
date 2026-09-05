defmodule Aludel.Providers.Provider do
  @moduledoc """
  Schema for AI provider configurations.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Aludel.Providers.ConfigPolicy
  alias Ecto.Changeset

  @type t :: %__MODULE__{}

  @required_fields ~w(name provider model)a
  @optional_fields ~w(config pricing)a
  @virtual_fields ~w(model_selection model_custom custom_pricing_enabled pricing_input pricing_output)a

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "providers" do
    field :name, :string

    field :provider, Ecto.Enum,
      values: [:openai, :anthropic, :ollama, :google, :xai, :groq, :openrouter]

    field :model, :string
    field :config, :map, redact: true
    field :pricing, :map
    field :model_selection, :string, virtual: true
    field :model_custom, :string, virtual: true
    field :custom_pricing_enabled, :boolean, virtual: true, default: false
    field :pricing_input, :string, virtual: true
    field :pricing_output, :string, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a provider.
  """
  @spec changeset(t(), map()) :: Changeset.t()
  def changeset(provider, attrs) do
    provider
    |> cast(attrs, @required_fields ++ @optional_fields ++ @virtual_fields)
    |> normalize_model()
    |> validate_required(@required_fields)
    |> validate_config()
    |> validate_pricing()
    |> check_constraint(:config,
      name: :providers_config_no_credentials,
      message: ConfigPolicy.error_message()
    )
  end

  defp validate_config(changeset) do
    validate_change(changeset, :config, fn :config, config ->
      case ConfigPolicy.validate(config) do
        :ok -> []
        {:error, :credentials_not_allowed} -> [config: ConfigPolicy.error_message()]
      end
    end)
  end

  defp validate_pricing(changeset) do
    validate_change(changeset, :pricing, fn :pricing, pricing ->
      cond do
        is_nil(pricing) ->
          []

        not is_map(pricing) ->
          [pricing: "must be a map"]

        true ->
          input = pricing["input"] || pricing[:input]
          output = pricing["output"] || pricing[:output]

          cond do
            not is_number(input) -> [pricing: "must contain a numeric input rate"]
            not is_number(output) -> [pricing: "must contain a numeric output rate"]
            true -> []
          end
      end
    end)
  end

  defp normalize_model(changeset) do
    selection = get_field(changeset, :model_selection)

    model =
      case selection do
        "custom" -> get_field(changeset, :model_custom)
        value when is_binary(value) and value != "" -> value
        _ -> get_field(changeset, :model)
      end

    if is_nil(model) or model == "" do
      changeset
    else
      put_change(changeset, :model, model)
    end
  end
end
