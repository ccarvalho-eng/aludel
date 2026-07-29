defmodule Aludel.Providers.PricingTest do
  use ExUnit.Case, async: true

  alias Aludel.Providers.Pricing

  describe "get_pricing/3" do
    test "returns custom pricing override with atom keys" do
      custom = %{input: 10.0, output: 30.0}
      assert Pricing.get_pricing(:openai, "gpt-4o", custom) == %{input: 10.0, output: 30.0}
    end

    test "returns custom pricing override with string keys" do
      custom = %{"input" => 5.0, "output" => 15.0}

      assert Pricing.get_pricing(:anthropic, "claude-sonnet-4-6", custom) == %{
               input: 5.0,
               output: 15.0
             }
    end

    test "returns LLMDB pricing for known model when no custom pricing" do
      result = Pricing.get_pricing(:anthropic, "claude-sonnet-4-20250514")

      assert result != nil
      assert is_number(result.input)
      assert is_number(result.output)
      assert result.input > 0
      assert result.output > 0
    end

    test "returns LLMDB pricing for openai model" do
      result = Pricing.get_pricing(:openai, "gpt-4o")

      assert result != nil
      assert is_number(result.input)
      assert is_number(result.output)
    end

    test "returns nil for unknown model" do
      assert Pricing.get_pricing(:openai, "nonexistent-model-xyz") == nil
    end

    test "returns free pricing for any ollama model" do
      assert Pricing.get_pricing(:ollama, "llama3.2") == %{input: 0.0, output: 0.0}
      assert Pricing.get_pricing(:ollama, "mistral") == %{input: 0.0, output: 0.0}
      assert Pricing.get_pricing(:ollama, "unknown-local-model") == %{input: 0.0, output: 0.0}
    end

    test "resolves canonical LLMDB models across providers" do
      # gpt-4o and claude-haiku-4-5-20251001 are canonical LLMDB models
      result_openai = Pricing.get_pricing(:openai, "gpt-4o")
      assert result_openai != nil
      assert is_number(result_openai.input)
      assert is_number(result_openai.output)

      result_anthropic = Pricing.get_pricing(:anthropic, "claude-haiku-4-5-20251001")
      assert result_anthropic != nil
      assert is_number(result_anthropic.input)
      assert is_number(result_anthropic.output)
    end

    test "ignores invalid custom pricing map without required keys" do
      result = Pricing.get_pricing(:openai, "gpt-4o", %{foo: "bar"})

      # Falls through to compile-time defaults since custom pricing lacks input/output
      assert result != nil
      assert is_number(result.input)
    end

    test "ignores nil custom pricing" do
      result = Pricing.get_pricing(:openai, "gpt-4o", nil)

      assert result != nil
      assert is_number(result.input)
    end
  end

  describe "format_pricing/1" do
    test "formats normal pricing" do
      assert Pricing.format_pricing(%{input: 3.0, output: 15.0}) ==
               "$3.00 / $15.00 per 1M tokens"
    end

    test "formats small pricing values" do
      assert Pricing.format_pricing(%{input: 0.15, output: 0.60}) ==
               "$0.15 / $0.60 per 1M tokens"
    end

    test "formats zero pricing as free" do
      assert Pricing.format_pricing(%{input: 0, output: 0}) == "Free"
    end

    test "formats zero float pricing as free" do
      assert Pricing.format_pricing(%{input: 0.0, output: 0.0}) == "Free"
    end

    test "formats nil as unknown" do
      assert Pricing.format_pricing(nil) == "Unknown"
    end
  end
end
