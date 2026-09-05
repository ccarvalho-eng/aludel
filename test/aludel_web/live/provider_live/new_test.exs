defmodule Aludel.Web.ProviderLive.NewTest do
  use Aludel.Web.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Aludel.ProvidersFixtures

  alias Aludel.Providers

  describe "new provider page" do
    test "renders the provider form", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/providers/new")

      assert has_element?(view, "#provider-form")
      assert has_element?(view, "#provider-form input[name='provider[name]']")
      assert has_element?(view, "#provider-form select[name='provider[model_selection]']")
      assert has_element?(view, "#provider_provider-select[phx-hook='CustomSelect']")
      assert has_element?(view, "#provider_provider[data-select-input]")
      assert has_element?(view, "#pricing-section.pricing-panel")
      assert has_element?(view, "#pricing-section-heading", "Pricing")
      assert has_element?(view, "#default-pricing-display.pricing-panel-meta")
      assert has_element?(view, "#pricing-default-indicator .pricing-default-indicator-icon")

      assert has_element?(
               view,
               "#pricing-section-copy",
               "Default model pricing is applied automatically"
             )
    end

    test "renders custom pricing steppers when pricing override is enabled", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/providers/new")

      html =
        view
        |> form("#provider-form", provider: %{custom_pricing_enabled: "true"})
        |> render_change()

      assert html =~ "data-stepper-direction=\"decrement\""
      assert has_element?(view, "#provider_pricing_input-stepper")
      assert has_element?(view, "#provider_pricing_output-stepper")
      refute has_element?(view, "#default-pricing-display")
    end

    test "prefills custom pricing inputs from default pricing when enabled", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/providers/new")

      default_pricing = Providers.default_pricing("openai", "gpt-4o")
      assert default_pricing

      render_change(view, :validate, %{
        "provider" => %{
          "provider" => "openai",
          "model_selection" => "gpt-4o",
          "custom_pricing_enabled" => "true",
          "pricing_input" => "",
          "pricing_output" => ""
        }
      })

      assert has_element?(
               view,
               "#provider_pricing_input[value='#{format_price(default_pricing.input)}']"
             )

      assert has_element?(
               view,
               "#provider_pricing_output[value='#{format_price(default_pricing.output)}']"
             )
    end

    test "refreshes auto-filled custom pricing when the selected model changes", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/providers/new")

      {first_model, second_model, first_pricing, second_pricing} = distinct_openai_pricing_pair()

      render_change(view, :validate, %{
        "provider" => %{
          "provider" => "openai",
          "model_selection" => first_model,
          "custom_pricing_enabled" => "true",
          "pricing_input" => "",
          "pricing_output" => ""
        }
      })

      render_change(view, :validate, %{
        "provider" => %{
          "provider" => "openai",
          "model_selection" => second_model,
          "custom_pricing_enabled" => "true",
          "pricing_input" => format_price(first_pricing.input),
          "pricing_output" => format_price(first_pricing.output)
        }
      })

      assert has_element?(
               view,
               "#provider_pricing_input[value='#{format_price(second_pricing.input)}']"
             )

      assert has_element?(
               view,
               "#provider_pricing_output[value='#{format_price(second_pricing.output)}']"
             )
    end

    test "clears auto-filled custom pricing when the next model has no default pricing", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/providers/new")

      default_pricing = Providers.default_pricing("openai", "gpt-4o")
      assert default_pricing

      render_change(view, :validate, %{
        "provider" => %{
          "provider" => "openai",
          "model_selection" => "gpt-4o",
          "custom_pricing_enabled" => "true",
          "pricing_input" => "",
          "pricing_output" => ""
        }
      })

      render_change(view, :validate, %{
        "provider" => %{
          "provider" => "openai",
          "model_selection" => "custom",
          "model_custom" => "my-unpriced-model",
          "custom_pricing_enabled" => "true",
          "pricing_input" => format_price(default_pricing.input),
          "pricing_output" => format_price(default_pricing.output)
        }
      })

      assert has_element?(view, "#provider_pricing_input[value='']")
      assert has_element?(view, "#provider_pricing_output[value='']")
    end

    test "shows custom input when custom model is selected", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/providers/new")

      html =
        view
        |> form("#provider-form", provider: %{provider: "openai", model_selection: "custom"})
        |> render_change()

      assert html =~ "Custom model name"
    end

    test "renders grouped model options through the shared select component", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/providers/new")

      html =
        view
        |> form("#provider-form", provider: %{provider: "openai", model_selection: "custom"})
        |> render_change()

      assert html =~ "GPT-4o"
      assert has_element?(view, "#provider_model_selection-select [data-select-option]", "Custom")
    end

    test "creates provider with valid data", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/providers/new")

      view
      |> form("#provider-form", provider: %{provider: "openai", model_selection: "custom"})
      |> render_change()

      view
      |> form("#provider-form",
        provider: %{
          name: "Configured Provider",
          provider: "openai",
          model_selection: "custom",
          model_custom: "gpt-4.1",
          config: ~s({"temperature":0.2,"max_tokens":512})
        }
      )
      |> render_submit()

      assert_redirect(view, "/providers")

      [provider] = Providers.list_providers()
      assert provider.name == "Configured Provider"
      assert provider.provider == :openai
      assert provider.model == "gpt-4.1"
      assert provider.config == %{"temperature" => 0.2, "max_tokens" => 512}
    end

    test "rejects credential configuration without rendering its value", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/providers/new")

      view
      |> form("#provider-form", provider: %{provider: "openai", model_selection: "custom"})
      |> render_change()

      html =
        view
        |> form("#provider-form",
          provider: %{
            name: "Unsafe Provider",
            provider: "openai",
            model_selection: "custom",
            model_custom: "gpt-4.1",
            config: ~s({"temperature":0.2,"api_key":"sensitive-value"})
          }
        )
        |> render_submit()

      assert html =~ "must not contain credentials; configure them at runtime"
      assert html =~ "temperature"
      refute html =~ "sensitive-value"
      refute html =~ "api_key"
      assert Providers.list_providers() == []
    end

    test "does not reflect credential values from malformed configuration", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/providers/new")

      view
      |> form("#provider-form", provider: %{provider: "openai", model_selection: "custom"})
      |> render_change()

      html =
        view
        |> form("#provider-form",
          provider: %{
            name: "Unsafe Provider",
            provider: "openai",
            model_selection: "custom",
            model_custom: "gpt-4.1",
            config: ~s({"api_secret":"sensitive-value")
          }
        )
        |> render_submit()

      refute html =~ "sensitive-value"
      refute html =~ "api_secret"
      assert Providers.list_providers() == []
    end

    test "does not reflect credential values from non-object configuration", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/providers/new")

      view
      |> form("#provider-form", provider: %{provider: "openai", model_selection: "custom"})
      |> render_change()

      html =
        view
        |> form("#provider-form",
          provider: %{
            name: "Unsafe Provider",
            provider: "openai",
            model_selection: "custom",
            model_custom: "gpt-4.1",
            config: ~s([{"aws_session_token":"sensitive-value"}])
          }
        )
        |> render_submit()

      refute html =~ "sensitive-value"
      refute html =~ "aws_session_token"
      assert Providers.list_providers() == []
    end

    test "shows Google Gemini in provider type dropdown", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/providers/new")

      assert html =~ "Google Gemini"
    end

    test "shows the expanded providers in the provider type dropdown", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/providers/new")

      assert has_element?(view, "#provider_provider option[value='xai']", "xAI")
      assert has_element?(view, "#provider_provider option[value='groq']", "Groq")

      assert has_element?(
               view,
               "#provider_provider option[value='openrouter']",
               "OpenRouter"
             )
    end

    test "creates an xAI provider through the form", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/providers/new")

      view
      |> form("#provider-form", provider: %{provider: "xai", model_selection: "custom"})
      |> render_change()

      view
      |> form("#provider-form",
        provider: %{
          name: "xAI Grok",
          provider: "xai",
          model_selection: "custom",
          model_custom: "grok-4",
          config: ~s({"temperature":0.4})
        }
      )
      |> render_submit()

      assert_redirect(view, "/providers")

      [provider] = Providers.list_providers()
      assert provider.provider == :xai
      assert provider.model == "grok-4"
    end

    test "creates a Gemini provider through the form", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/providers/new")

      view
      |> form("#provider-form", provider: %{provider: "google", model_selection: "custom"})
      |> render_change()

      view
      |> form("#provider-form",
        provider: %{
          name: "Gemini Flash",
          provider: "google",
          model_selection: "custom",
          model_custom: "gemini-2.5-flash",
          config: ~s({"temperature":0.7,"max_tokens":1024})
        }
      )
      |> render_submit()

      assert_redirect(view, "/providers")

      [provider] = Providers.list_providers()
      assert provider.name == "Gemini Flash"
      assert provider.provider == :google
      assert provider.model == "gemini-2.5-flash"
    end

    test "shows validation errors for invalid data", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/providers/new")

      view
      |> form("#provider-form",
        provider: %{
          name: "",
          provider: "",
          model_selection: ""
        }
      )
      |> render_submit()

      assert has_element?(view, "#provider_name.input-error")
      assert has_element?(view, "#provider_provider.select-error")
      refute has_element?(view, "#provider_model_selection.select-error")
    end
  end

  describe "provider editing" do
    test "keeps an existing model selectable during edit", %{conn: conn} do
      provider =
        provider_fixture(%{
          name: "Existing Provider",
          provider: :openai,
          model: "gpt-4o"
        })

      {:ok, view, _html} = live(conn, "/providers/#{provider.id}/edit")

      assert has_element?(view, "#provider-form")
      assert has_element?(view, "#provider-form select[name='provider[model_selection]']")
    end

    test "loads unknown saved model as custom during edit", %{conn: conn} do
      provider =
        provider_fixture(%{
          name: "Custom Provider",
          provider: :openai,
          model: "my-custom-model"
        })

      {:ok, view, html} = live(conn, "/providers/#{provider.id}/edit")

      assert html =~ "Custom model name"
      assert has_element?(view, "#provider_model_custom[value='my-custom-model']")
      assert has_element?(view, "#provider_model_selection option[value='custom'][selected]")
    end

    test "updates provider with valid data", %{conn: conn} do
      provider = provider_fixture()

      {:ok, view, _html} = live(conn, "/providers/#{provider.id}/edit")

      view
      |> form("#provider-form", provider: %{provider: "openrouter", model_selection: "custom"})
      |> render_change()

      view
      |> form("#provider-form",
        provider: %{
          name: "Updated Provider",
          provider: "openrouter",
          model_selection: "custom",
          model_custom: "anthropic/claude-sonnet-4",
          config: ~s({"temperature":0.4})
        }
      )
      |> render_submit()

      assert_redirect(view, "/providers")

      updated_provider = Providers.get_provider!(provider.id)
      assert updated_provider.name == "Updated Provider"
      assert updated_provider.provider == :openrouter
      assert updated_provider.model == "anthropic/claude-sonnet-4"
      assert updated_provider.config == %{"temperature" => 0.4}
    end

    test "clears stale model selection when provider changes", %{conn: conn} do
      provider = provider_fixture(%{provider: :openai, model: "gpt-4o"})

      {:ok, view, _html} = live(conn, "/providers/#{provider.id}/edit")

      render_change(
        view,
        :validate,
        %{provider: %{provider: "anthropic", model_selection: "gpt-4o"}}
      )

      refute has_element?(view, "#provider_model_selection option[value='gpt-4o'][selected]")
      selected_model = Providers.fetch_models(:anthropic) |> hd() |> Map.fetch!(:id)

      view
      |> form("#provider-form",
        provider: %{
          provider: "anthropic",
          model_selection: selected_model,
          name: "OpenAI GPT-4o",
          config: ~s({})
        }
      )
      |> render_submit()

      reloaded_provider = Providers.get_provider!(provider.id)
      assert reloaded_provider.provider == :anthropic
      assert reloaded_provider.model == selected_model
    end

    test "keeps provider unchanged when invalid data is submitted", %{conn: conn} do
      provider = provider_fixture(%{name: "Existing Provider", model: "gpt-4o"})

      {:ok, view, _html} = live(conn, "/providers/#{provider.id}/edit")

      view
      |> form("#provider-form",
        provider: %{
          name: "",
          provider: "",
          model_selection: ""
        }
      )
      |> render_submit()

      assert has_element?(view, "#provider_name.input-error")
      assert has_element?(view, "#provider_provider.select-error")
      refute has_element?(view, "#provider_model_selection.select-error")

      reloaded_provider = Providers.get_provider!(provider.id)
      assert reloaded_provider.name == "Existing Provider"
      assert reloaded_provider.model == "gpt-4o"
    end
  end

  defp format_price(value) when is_number(value) do
    :erlang.float_to_binary(value / 1, decimals: 2)
  end

  defp distinct_openai_pricing_pair do
    models = Providers.fetch_model_groups("openai").active

    models
    |> Enum.flat_map(fn first ->
      first_pricing = Providers.default_pricing("openai", first.id)

      Enum.map(models, fn second ->
        {first, second, first_pricing, Providers.default_pricing("openai", second.id)}
      end)
    end)
    |> Enum.find(fn {first, second, first_pricing, second_pricing} ->
      first.id != second.id and is_map(first_pricing) and is_map(second_pricing) and
        first_pricing != second_pricing
    end)
    |> case do
      {first, second, first_pricing, second_pricing} ->
        {first.id, second.id, first_pricing, second_pricing}

      nil ->
        raise "expected at least two OpenAI models with distinct default pricing"
    end
  end
end
