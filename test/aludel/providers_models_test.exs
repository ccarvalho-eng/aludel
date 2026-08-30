defmodule Aludel.ProvidersModelsTest do
  use ExUnit.Case, async: true

  alias Aludel.Providers

  describe "group_models/1" do
    test "splits active and deprecated models and sorts each group" do
      models = [
        %{id: "b-active", name: "Beta", deprecated: false},
        %{id: "a-deprecated", name: "Alpha", deprecated: true},
        %{id: "a-active", name: "Alpha", deprecated: false}
      ]

      assert %{active: active, deprecated: deprecated} = Providers.group_models(models)
      assert Enum.map(active, & &1.id) == ["a-active", "b-active"]
      assert Enum.map(deprecated, & &1.id) == ["a-deprecated"]
    end
  end

  describe "fetch_models/1" do
    test "returns active models only" do
      models = Providers.fetch_models(:openai)
      assert is_list(models)

      Enum.each(models, fn model ->
        assert Map.has_key?(model, :id)
        assert Map.has_key?(model, :name)
      end)
    end

    test "returns empty list for invalid provider" do
      assert Providers.fetch_models(:invalid) == []
    end
  end

  describe "fetch_model_groups/1" do
    test "returns active and deprecated groups" do
      groups = Providers.fetch_model_groups(:openai)

      assert Map.has_key?(groups, :active)
      assert Map.has_key?(groups, :deprecated)
      assert is_list(groups.active)
      assert is_list(groups.deprecated)
    end

    test "fetches model groups for google provider" do
      groups = Providers.fetch_model_groups(:google)

      assert Map.has_key?(groups, :active)
      assert Map.has_key?(groups, :deprecated)
      assert is_list(groups.active)
      assert is_list(groups.deprecated)
    end

    test "fetches model groups for google string type" do
      groups = Providers.fetch_model_groups("google")

      assert Map.has_key?(groups, :active)
      assert Map.has_key?(groups, :deprecated)
      assert is_list(groups.active)
      assert is_list(groups.deprecated)
    end

    test "returns empty groups for unknown provider string" do
      assert %{active: [], deprecated: []} = Providers.fetch_model_groups("unknown")
    end

    test "fetches text generation models for expanded provider string types" do
      for provider <- ~w(xai groq openrouter) do
        groups = Providers.fetch_model_groups(provider)

        assert groups.active != []
      end

      xai_ids = Providers.fetch_models("xai") |> Enum.map(& &1.id)
      groq_ids = Providers.fetch_models("groq") |> Enum.map(& &1.id)
      openrouter_ids = Providers.fetch_models("openrouter") |> Enum.map(& &1.id)

      refute "grok-imagine-image" in xai_ids
      refute "whisper-large-v3" in groq_ids
      refute "black-forest-labs/flux.2-klein-4b" in openrouter_ids
    end
  end

  describe "text_generation_model?/1" do
    test "accepts chat-capable and text-in/text-out models" do
      assert Providers.text_generation_model?(%{capabilities: %{chat: true}, modalities: nil})

      assert Providers.text_generation_model?(%{
               capabilities: nil,
               modalities: %{input: [:text, :image], output: [:text]}
             })
    end

    test "rejects transcription, image, and unknown-capability models" do
      refute Providers.text_generation_model?(%{
               capabilities: %{chat: false},
               modalities: %{input: [:audio], output: [:text]}
             })

      refute Providers.text_generation_model?(%{
               capabilities: nil,
               modalities: %{input: [:text], output: [:image]}
             })

      refute Providers.text_generation_model?(%{capabilities: nil, modalities: nil})
    end
  end
end
