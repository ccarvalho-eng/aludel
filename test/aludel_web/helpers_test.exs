defmodule Aludel.Web.HelpersTest do
  use ExUnit.Case, async: true

  alias Aludel.Web.Helpers
  alias Phoenix.LiveView.Socket

  describe "aludel_path/2" do
    test "returns / when routing is :nowhere" do
      Process.put(:routing, :nowhere)

      on_exit(fn -> Process.delete(:routing) end)

      path = Helpers.aludel_path("prompts")
      assert path == "/"
    end

    test "raises when routing is not set" do
      Process.delete(:routing)

      assert_raise RuntimeError, "nothing stored in the :routing key", fn ->
        Helpers.aludel_path("prompts")
      end
    end

    test "drops nil and blank query params" do
      socket = %Socket{router: Aludel.Web.Router, endpoint: Aludel.Web.Endpoint}
      Process.put(:routing, {socket, "/aludel"})

      on_exit(fn -> Process.delete(:routing) end)

      path =
        Helpers.aludel_path("prompts", %{
          "page" => "2",
          "project_id" => "",
          "search" => nil
        })

      assert path == "/aludel/prompts?page=2"
    end
  end

  describe "provider_icon/1" do
    test "returns OpenAI icon path" do
      assert Helpers.provider_icon(:openai) == "/images/open-ai-icon.svg"
    end

    test "returns Anthropic icon path" do
      assert Helpers.provider_icon(:anthropic) == "/images/anthropic-icon.svg"
    end

    test "returns Ollama icon path" do
      assert Helpers.provider_icon(:ollama) == "/images/ollama-icon.svg"
    end

    test "returns xAI's Grok icon path" do
      assert Helpers.provider_icon(:xai) == "/images/grok-icon.svg"
    end

    test "uses the fallback for providers without bundled icons" do
      assert Helpers.provider_icon(:groq) == nil
      assert Helpers.provider_icon(:openrouter) == nil
    end

    test "returns nil for unknown provider" do
      assert Helpers.provider_icon(:unknown) == nil
    end

    test "accepts provider struct and extracts enum" do
      provider = %{provider: :openai}
      assert Helpers.provider_icon(provider) == "/images/open-ai-icon.svg"
    end

    test "returns nil for invalid input" do
      assert Helpers.provider_icon("invalid") == nil
      assert Helpers.provider_icon(123) == nil
    end
  end
end
