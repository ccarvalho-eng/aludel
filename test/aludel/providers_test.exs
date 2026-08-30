defmodule Aludel.ProvidersTest do
  use Aludel.DataCase, async: true

  alias Aludel.Providers

  describe "providers" do
    test "list_providers/0 returns all providers" do
      provider = provider_fixture()
      assert Providers.list_providers() == [provider]
    end

    test "get_provider!/1 returns the provider with given id" do
      provider = provider_fixture()
      assert Providers.get_provider!(provider.id) == provider
    end

    test "create_provider/1 with valid data creates a provider" do
      attrs = %{
        name: "OpenAI GPT-4o",
        provider: :openai,
        model: "gpt-4o",
        config: %{"temperature" => 0.7, "max_tokens" => 1000}
      }

      assert {:ok, provider} = Providers.create_provider(attrs)
      assert provider.name == "OpenAI GPT-4o"
      assert provider.provider == :openai
      assert provider.model == "gpt-4o"
      assert provider.config == %{"temperature" => 0.7, "max_tokens" => 1000}
    end

    test "create_provider/1 with invalid provider enum returns error" do
      attrs = %{
        name: "Invalid Provider",
        provider: :invalid,
        model: "test-model",
        config: %{}
      }

      assert {:error, changeset} = Providers.create_provider(attrs)
      assert "is invalid" in errors_on(changeset).provider
    end

    test "create_provider/1 without name returns error" do
      attrs = %{
        provider: :openai,
        model: "gpt-4o",
        config: %{}
      }

      assert {:error, changeset} = Providers.create_provider(attrs)
      assert "can't be blank" in errors_on(changeset).name
    end

    test "create_provider/1 without provider returns error" do
      attrs = %{
        name: "Test Provider",
        model: "gpt-4o",
        config: %{}
      }

      assert {:error, changeset} = Providers.create_provider(attrs)
      assert "can't be blank" in errors_on(changeset).provider
    end

    test "create_provider/1 without model returns error" do
      attrs = %{
        name: "Test Provider",
        provider: :openai,
        config: %{}
      }

      assert {:error, changeset} = Providers.create_provider(attrs)
      assert "can't be blank" in errors_on(changeset).model
    end

    test "create_provider/1 with google provider" do
      attrs = %{
        name: "Google Gemini Flash",
        provider: :google,
        model: "gemini-2.5-flash",
        config: %{"temperature" => 0.7, "max_tokens" => 1024}
      }

      assert {:ok, provider} = Providers.create_provider(attrs)
      assert provider.name == "Google Gemini Flash"
      assert provider.provider == :google
      assert provider.model == "gemini-2.5-flash"
    end

    test "create_provider/1 accepts the expanded provider types" do
      for provider_type <- [:xai, :groq, :openrouter] do
        assert {:ok, provider} =
                 Providers.create_provider(%{
                   name: "#{provider_type} provider",
                   provider: provider_type,
                   model: "test-model",
                   config: %{}
                 })

        assert provider.provider == provider_type
      end
    end

    test "lists providers including google type" do
      _openai = provider_fixture(%{name: "OpenAI", provider: :openai, model: "gpt-4o"})

      _google =
        provider_fixture(%{name: "Gemini Flash", provider: :google, model: "gemini-2.5-flash"})

      providers = Providers.list_providers()
      assert length(providers) == 2
      assert Enum.any?(providers, fn p -> p.provider == :google end)
    end

    test "create_provider/1 with JSONB config storage" do
      attrs = %{
        name: "Anthropic Claude",
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022",
        config: %{
          "temperature" => 0.5,
          "max_tokens" => 2000,
          "top_p" => 1.0
        }
      }

      assert {:ok, provider} = Providers.create_provider(attrs)

      assert provider.config == %{
               "temperature" => 0.5,
               "max_tokens" => 2000,
               "top_p" => 1.0
             }
    end

    test "update_provider/2 with valid data updates the provider" do
      provider = provider_fixture()

      update_attrs = %{
        name: "Updated Name",
        model: "updated-model",
        config: %{"temperature" => 0.9}
      }

      assert {:ok, updated} = Providers.update_provider(provider, update_attrs)
      assert updated.name == "Updated Name"
      assert updated.model == "updated-model"
      assert updated.config == %{"temperature" => 0.9}
    end

    test "create_provider/1 accepts a custom model name" do
      attrs = %{
        name: "Custom Provider",
        provider: :openai,
        model: "my-custom-model",
        model_selection: "custom",
        model_custom: "my-custom-model",
        config: %{}
      }

      assert {:ok, provider} = Providers.create_provider(attrs)
      assert provider.model == "my-custom-model"
    end

    test "update_provider/2 with invalid data returns error" do
      provider = provider_fixture()
      assert {:error, changeset} = Providers.update_provider(provider, %{name: nil})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "delete_provider/1 deletes the provider" do
      provider = provider_fixture()
      assert {:ok, _} = Providers.delete_provider(provider)
      assert_raise Ecto.NoResultsError, fn -> Providers.get_provider!(provider.id) end
    end

    test "change_provider/1 returns a provider changeset" do
      provider = provider_fixture()
      assert %Ecto.Changeset{} = Providers.change_provider(provider)
    end

    test "change_provider/2 returns a provider changeset with changes" do
      provider = provider_fixture()
      changeset = Providers.change_provider(provider, %{name: "New Name"})
      assert %Ecto.Changeset{} = changeset
      assert changeset.changes.name == "New Name"
    end
  end

  describe "build_pricing_attrs/2" do
    test "sets pricing to nil when custom pricing is disabled" do
      params = %{"pricing_input" => "5.0", "pricing_output" => "15.0"}
      result = Providers.build_pricing_attrs(params, false)
      assert result["pricing"] == nil
    end

    test "parses valid numeric strings into a pricing map when enabled" do
      params = %{"pricing_input" => "5.0", "pricing_output" => "15.0"}
      result = Providers.build_pricing_attrs(params, true)
      assert result["pricing"] == %{"input" => 5.0, "output" => 15.0}
    end

    test "forwards raw strings when pricing_input is invalid so changeset can validate" do
      params = %{"pricing_input" => "not-a-number", "pricing_output" => "15.0"}
      result = Providers.build_pricing_attrs(params, true)
      assert result["pricing"] == %{"input" => "not-a-number", "output" => "15.0"}
    end

    test "forwards raw strings when pricing_output is invalid so changeset can validate" do
      params = %{"pricing_input" => "5.0", "pricing_output" => "bad"}
      result = Providers.build_pricing_attrs(params, true)
      assert result["pricing"] == %{"input" => "5.0", "output" => "bad"}
    end

    test "forwards raw values when only pricing_input is empty so changeset can validate" do
      params = %{"pricing_input" => "", "pricing_output" => "15.0"}
      result = Providers.build_pricing_attrs(params, true)
      assert result["pricing"] == %{"input" => "", "output" => "15.0"}
    end

    test "forwards raw values when only pricing_output is empty so changeset can validate" do
      params = %{"pricing_input" => "5.0", "pricing_output" => ""}
      result = Providers.build_pricing_attrs(params, true)
      assert result["pricing"] == %{"input" => "5.0", "output" => ""}
    end

    test "sets pricing to nil when both inputs are empty strings and enabled" do
      params = %{"pricing_input" => "", "pricing_output" => ""}
      result = Providers.build_pricing_attrs(params, true)
      assert result["pricing"] == nil
    end

    test "sets pricing to nil when inputs are nil and enabled" do
      params = %{"pricing_input" => nil, "pricing_output" => nil}
      result = Providers.build_pricing_attrs(params, true)
      assert result["pricing"] == nil
    end

    test "preserves other params untouched" do
      params = %{"name" => "My Provider", "pricing_input" => "1.0", "pricing_output" => "2.0"}
      result = Providers.build_pricing_attrs(params, true)
      assert result["name"] == "My Provider"
    end
  end

  describe "default_pricing/2" do
    test "returns nil when provider is nil" do
      assert Providers.default_pricing(nil, "gpt-4o") == nil
    end

    test "returns nil when model is nil" do
      assert Providers.default_pricing(:openai, nil) == nil
    end

    test "returns nil when model is an empty string" do
      assert Providers.default_pricing(:openai, "") == nil
    end

    test "returns free pricing for ollama" do
      result = Providers.default_pricing(:ollama, "llama3")
      assert result == %{input: 0.0, output: 0.0}
    end

    test "returns a pricing map with input and output rates for known models" do
      result = Providers.default_pricing(:openai, "gpt-4o")
      assert is_map(result)
      assert is_number(result[:input] || result["input"])
      assert is_number(result[:output] || result["output"])
    end

    test "accepts provider as a binary string" do
      result = Providers.default_pricing("openai", "gpt-4o")
      assert is_map(result)
    end

    test "returns nil for an unknown model" do
      assert Providers.default_pricing(:openai, "non-existent-model-xyz") == nil
    end
  end

  describe "pricing_form_attrs/1" do
    test "returns empty strings and false when provider has no custom pricing" do
      provider = provider_fixture()
      result = Providers.pricing_form_attrs(provider)

      assert result == %{
               custom_pricing_enabled: false,
               pricing_input: "",
               pricing_output: ""
             }
    end

    test "returns pricing values and true when provider has custom pricing with string keys" do
      provider = provider_fixture(%{pricing: %{"input" => 3.0, "output" => 9.0}})
      result = Providers.pricing_form_attrs(provider)

      assert result == %{
               custom_pricing_enabled: true,
               pricing_input: "3.0",
               pricing_output: "9.0"
             }
    end

    test "returns pricing values and true when provider has custom pricing with atom keys" do
      provider = provider_fixture(%{pricing: %{input: 2.5, output: 7.5}})
      result = Providers.pricing_form_attrs(provider)

      assert result == %{
               custom_pricing_enabled: true,
               pricing_input: "2.5",
               pricing_output: "7.5"
             }
    end

    test "returns false when provider pricing is an empty map" do
      provider = provider_fixture()
      # Simulate a provider with an empty pricing map (no custom override)
      provider_with_empty_pricing = %{provider | pricing: %{}}
      result = Providers.pricing_form_attrs(provider_with_empty_pricing)
      assert result.custom_pricing_enabled == false
    end
  end
end
