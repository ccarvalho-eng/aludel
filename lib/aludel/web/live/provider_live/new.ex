defmodule Aludel.Web.ProviderLive.New do
  @moduledoc """
  LiveView for creating and editing AI providers.
  """

  use Aludel.Web, :live_view

  alias Aludel.Providers
  alias Aludel.Providers.ConfigPolicy
  alias Aludel.Providers.Provider

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    model_groups = %{active: [], deprecated: []}

    {:ok,
     assign(socket,
       model_groups: model_groups,
       model_options: model_options(model_groups)
     )}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    socket = apply_action(socket, socket.assigns.live_action, params)
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"provider" => provider_params}, socket) do
    config_json = Map.get(provider_params, "config", "")
    provider_type = provider_params["provider"]
    model_groups = Providers.fetch_model_groups(provider_type)

    custom_pricing_enabled = provider_params["custom_pricing_enabled"] == "true"
    model = resolve_model(provider_params, model_groups)
    default_pricing = Providers.default_pricing(provider_type, model)

    {pricing_input, pricing_output} =
      resolve_pricing_inputs(
        provider_params["pricing_input"],
        provider_params["pricing_output"],
        custom_pricing_enabled,
        default_pricing,
        socket.assigns.default_pricing
      )

    changeset =
      socket.assigns.provider
      |> Providers.change_provider(
        provider_params
        |> parse_config()
        |> Map.merge(%{
          "custom_pricing_enabled" => custom_pricing_enabled,
          "pricing_input" => pricing_input,
          "pricing_output" => pricing_output
        })
      )
      |> ensure_model_selection(model_groups)
      |> validate_model_selection()
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:model_groups, model_groups)
     |> assign(:model_options, model_options(model_groups))
     |> assign(:form, to_form(changeset))
     |> assign(:config_json, safe_config_json(config_json, changeset))
     |> assign(:default_pricing, default_pricing)
     |> assign(:custom_pricing_enabled, custom_pricing_enabled)
     |> assign(:pricing_input, pricing_input)
     |> assign(:pricing_output, pricing_output)}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"provider" => provider_params}, socket) do
    custom_pricing_enabled = provider_params["custom_pricing_enabled"] == "true"

    provider_params =
      Providers.build_pricing_attrs(provider_params, custom_pricing_enabled)

    save_provider(socket, socket.assigns.live_action, provider_params)
  end

  defp apply_action(socket, :new, _params) do
    model_groups = %{active: [], deprecated: []}

    changeset =
      Providers.change_provider(%Provider{}, %{
        "custom_pricing_enabled" => false,
        "pricing_input" => "",
        "pricing_output" => ""
      })

    socket
    |> assign(:page_title, "New Provider")
    |> assign(:provider, %Provider{})
    |> assign(:model_groups, model_groups)
    |> assign(:model_options, model_options(model_groups))
    |> assign(:config_json, "")
    |> assign(:form, to_form(changeset))
    |> assign(:default_pricing, nil)
    |> assign(:custom_pricing_enabled, false)
    |> assign(:pricing_input, "")
    |> assign(:pricing_output, "")
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    provider = Providers.get_provider!(id)
    model_groups = Providers.fetch_model_groups(provider.provider)

    %{
      custom_pricing_enabled: has_custom_pricing,
      pricing_input: pricing_input,
      pricing_output: pricing_output
    } = Providers.pricing_form_attrs(provider)

    changeset =
      provider
      |> Providers.change_provider(%{
        "custom_pricing_enabled" => has_custom_pricing,
        "pricing_input" => pricing_input,
        "pricing_output" => pricing_output
      })
      |> ensure_model_selection(model_groups)
      |> validate_model_selection()

    default_pricing = Providers.default_pricing(provider.provider, provider.model)

    socket
    |> assign(:page_title, "Edit Provider")
    |> assign(:provider, provider)
    |> assign(:model_groups, model_groups)
    |> assign(:model_options, model_options(model_groups))
    |> assign(:config_json, provider.config |> ConfigPolicy.sanitize() |> encode_config())
    |> assign(:form, to_form(changeset))
    |> assign(:default_pricing, default_pricing)
    |> assign(:custom_pricing_enabled, has_custom_pricing)
    |> assign(:pricing_input, pricing_input)
    |> assign(:pricing_output, pricing_output)
  end

  defp save_provider(socket, :new, provider_params) do
    config_json = Map.get(provider_params, "config", "")

    # Parse config JSON if provided
    provider_params = provider_params |> normalize_model_params() |> parse_config()

    case Providers.create_provider(provider_params) do
      {:ok, _provider} ->
        {:noreply,
         socket
         |> put_flash(:info, "Provider created successfully")
         |> push_navigate(to: aludel_path("providers"))}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset))
         |> assign(:config_json, safe_config_json(config_json, changeset))}
    end
  end

  defp save_provider(socket, :edit, provider_params) do
    config_json = Map.get(provider_params, "config", "")

    # Parse config JSON if provided
    provider_params = provider_params |> normalize_model_params() |> parse_config()

    case Providers.update_provider(socket.assigns.provider, provider_params) do
      {:ok, _provider} ->
        {:noreply,
         socket
         |> put_flash(:info, "Provider updated successfully")
         |> push_navigate(to: aludel_path("providers"))}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset))
         |> assign(:config_json, safe_config_json(config_json, changeset))}
    end
  end

  defp parse_config(params) do
    case params["config"] do
      nil ->
        params

      "" ->
        Map.put(params, "config", %{})

      config_str ->
        case Jason.decode(config_str) do
          {:ok, config} -> Map.put(params, "config", config)
          {:error, _} -> params
        end
    end
  end

  defp encode_config(nil), do: ""
  defp encode_config(config) when map_size(config) == 0, do: ""
  defp encode_config(config), do: Jason.encode!(config, pretty: true)

  defp safe_config_json(config_json, changeset) do
    if credential_config_error?(changeset) or credential_key_in_json?(config_json) do
      sanitize_config_json(config_json)
    else
      config_json
    end
  end

  defp credential_config_error?(changeset) do
    Enum.any?(changeset.errors, fn
      {:config, {message, _opts}} -> message == ConfigPolicy.error_message()
      _other -> false
    end)
  end

  defp sanitize_config_json(config_json) when is_binary(config_json) do
    case Jason.decode(config_json) do
      {:ok, config} when is_map(config) ->
        config
        |> ConfigPolicy.sanitize()
        |> encode_config()

      _invalid_or_non_map ->
        ""
    end
  end

  defp sanitize_config_json(_config_json) do
    ""
  end

  defp credential_key_in_json?(config_json) when is_binary(config_json) do
    case Jason.decode(config_json) do
      {:ok, config} ->
        ConfigPolicy.validate(config) != :ok

      {:error, _reason} ->
        credential_key_in_malformed_json?(config_json)
    end
  end

  defp credential_key_in_json?(_config_json) do
    false
  end

  defp credential_key_in_malformed_json?(config_json) do
    ~r/"((?:\\.|[^"\\])*)"\s*:/u
    |> Regex.scan(config_json, capture: :all_but_first)
    |> Enum.any?(&encoded_credential_key?/1)
  end

  defp encoded_credential_key?([encoded_key]) do
    case Jason.decode(~s("#{encoded_key}")) do
      {:ok, key} -> ConfigPolicy.validate(%{key => nil}) != :ok
      {:error, _reason} -> false
    end
  end

  defp normalize_model_params(params) do
    case params["model_selection"] do
      "custom" -> Map.put(params, "model", params["model_custom"])
      value when is_binary(value) and value != "" -> Map.put(params, "model", value)
      _ -> params
    end
  end

  defp ensure_model_selection(changeset, model_groups) do
    selection = Ecto.Changeset.get_field(changeset, :model_selection)
    model = Ecto.Changeset.get_field(changeset, :model)
    custom_model = Ecto.Changeset.get_field(changeset, :model_custom)

    cond do
      custom_selection?(selection) ->
        changeset
        |> Ecto.Changeset.put_change(:model_custom, custom_model)
        |> Ecto.Changeset.put_change(:model, custom_model)

      valid_selection?(model_groups, selection) ->
        changeset
        |> Ecto.Changeset.put_change(:model_selection, selection)
        |> Ecto.Changeset.put_change(:model, selection)
        |> Ecto.Changeset.delete_change(:model_custom)

      invalid_selection?(selection) ->
        changeset
        |> Ecto.Changeset.put_change(:model_selection, nil)
        |> Ecto.Changeset.put_change(:model, nil)
        |> Ecto.Changeset.delete_change(:model_custom)

      model_in_groups?(model_groups, model) ->
        changeset
        |> Ecto.Changeset.put_change(:model_selection, model)
        |> Ecto.Changeset.put_change(:model, model)
        |> Ecto.Changeset.delete_change(:model_custom)

      is_binary(model) and model != "" ->
        changeset
        |> Ecto.Changeset.put_change(:model_selection, "custom")
        |> Ecto.Changeset.put_change(:model_custom, model)

      true ->
        changeset
    end
  end

  defp custom_selection?(selection), do: selection == "custom"

  defp valid_selection?(model_groups, selection) do
    present_value?(selection) and model_in_groups?(model_groups, selection)
  end

  defp invalid_selection?(selection), do: present_value?(selection)

  defp present_value?(value), do: is_binary(value) and value != ""

  defp model_in_groups?(%{active: active, deprecated: deprecated}, model) do
    Enum.any?(active ++ deprecated, &(&1.id == model))
  end

  defp model_options(%{active: active, deprecated: deprecated}) do
    [
      {"Active models", Enum.map(active, &{&1.name, &1.id})},
      {"Deprecated models", Enum.map(deprecated, &{&1.name, &1.id})},
      {"Custom model", [{"Custom", "custom"}]}
    ]
  end

  defp validate_model_selection(changeset) do
    case Ecto.Changeset.get_field(changeset, :model_selection) do
      nil -> Ecto.Changeset.add_error(changeset, :model_selection, "can't be blank")
      "" -> Ecto.Changeset.add_error(changeset, :model_selection, "can't be blank")
      "custom" -> Ecto.Changeset.validate_required(changeset, [:model_custom])
      _ -> changeset
    end
  end

  defp resolve_model(params, _model_groups) do
    case params["model_selection"] do
      "custom" -> params["model_custom"]
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp resolve_pricing_inputs(
         pricing_input,
         pricing_output,
         true,
         %{input: input, output: output},
         previous_default_pricing
       ) do
    if (blank_string?(pricing_input) and blank_string?(pricing_output)) or
         matches_default_pricing?(pricing_input, pricing_output, previous_default_pricing) do
      {format_price(input), format_price(output)}
    else
      {pricing_input || "", pricing_output || ""}
    end
  end

  defp resolve_pricing_inputs(
         pricing_input,
         pricing_output,
         true,
         nil,
         previous_default_pricing
       ) do
    if (blank_string?(pricing_input) and blank_string?(pricing_output)) or
         matches_default_pricing?(pricing_input, pricing_output, previous_default_pricing) do
      {"", ""}
    else
      {pricing_input || "", pricing_output || ""}
    end
  end

  defp resolve_pricing_inputs(
         pricing_input,
         pricing_output,
         _custom_pricing_enabled,
         _default_pricing,
         _previous_default_pricing
       ) do
    {pricing_input || "", pricing_output || ""}
  end

  defp blank_string?(value), do: value in [nil, ""]

  defp matches_default_pricing?(_pricing_input, _pricing_output, nil), do: false

  defp matches_default_pricing?(pricing_input, pricing_output, %{input: input, output: output}) do
    pricing_input == format_price(input) and pricing_output == format_price(output)
  end

  defp format_price(value) when is_number(value) do
    :erlang.float_to_binary(value / 1, decimals: 2)
  end
end
