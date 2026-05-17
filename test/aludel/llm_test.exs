defmodule Aludel.LLMTest do
  use Aludel.DataCase, async: false

  import Mox

  alias Aludel.Interfaces.HttpClientMock
  alias Aludel.LLM

  setup :verify_on_exit!

  describe "call/3 with OpenAI provider" do
    test "returns error when API key is missing" do
      original_config = Application.get_env(:aludel, :llm)
      Application.put_env(:aludel, :llm, openai_api_key: nil)

      try do
        provider =
          provider_fixture(%{
            provider: :openai,
            model: "gpt-4o",
            config: %{}
          })

        assert {:error, :missing_api_key} = LLM.call(provider, "test", [])
      after
        Application.put_env(:aludel, :llm, original_config)
      end
    end

    test "returns error when API key is empty string" do
      original_config = Application.get_env(:aludel, :llm)
      Application.put_env(:aludel, :llm, openai_api_key: "")

      try do
        provider =
          provider_fixture(%{
            provider: :openai,
            model: "gpt-4o",
            config: %{}
          })

        assert {:error, :missing_api_key} = LLM.call(provider, "test", [])
      after
        Application.put_env(:aludel, :llm, original_config)
      end
    end

    test "returns structured response with all required fields" do
      mock_response = build_mock_response("Hello! How can I help?", 5, 10)

      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      provider =
        provider_fixture(%{
          provider: :openai,
          model: "gpt-4o",
          config: %{"temperature" => 0.7}
        })

      assert {:ok, result} = LLM.call(provider, "test prompt", [])
      assert is_binary(result.output)
      assert result.output != ""
      assert is_integer(result.input_tokens)
      assert is_integer(result.output_tokens)
      assert is_integer(result.latency_ms)
      assert is_float(result.cost_usd)
      assert result.latency_ms >= 0
    end

    test "calculates cost for OpenAI" do
      mock_response = build_mock_response("Test response", 5, 10)

      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      provider =
        provider_fixture(%{
          provider: :openai,
          model: "gpt-4o",
          config: %{}
        })

      {:ok, result} = LLM.call(provider, "test", [])
      assert result.cost_usd > 0
    end

    test "calls OpenAI adapter successfully" do
      mock_response = build_mock_response("Hello!", 3, 2)

      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      provider =
        provider_fixture(%{
          provider: :openai,
          model: "gpt-4o",
          config: %{"temperature" => 0.7, "max_tokens" => 100}
        })

      assert {:ok, result} = LLM.call(provider, "Say hello", [])
      assert is_binary(result.output)
      assert result.output != ""
      assert result.input_tokens > 0
      assert result.output_tokens > 0
    end

    test "returns auth error for invalid API key" do
      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:error, %{status: 401}}
      end)

      provider =
        provider_fixture(%{
          provider: :openai,
          model: "gpt-4o",
          config: %{}
        })

      result = LLM.call(provider, "test", [])

      assert {:error, {:auth_error, _message}} = result
    end

    test "returns invalid_request error for bad parameters" do
      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:error, %{status: 400}}
      end)

      provider =
        provider_fixture(%{
          provider: :openai,
          model: "invalid-model-name",
          config: %{}
        })

      result = LLM.call(provider, "test", [])

      assert {:error, {:invalid_request, _}} = result
    end
  end

  describe "call/3 with Anthropic provider" do
    test "returns error when API key is missing" do
      original_config = Application.get_env(:aludel, :llm)
      Application.put_env(:aludel, :llm, anthropic_api_key: nil)

      try do
        provider =
          provider_fixture(%{
            provider: :anthropic,
            model: "claude-3-5-sonnet-20241022",
            config: %{}
          })

        assert {:error, :missing_api_key} = LLM.call(provider, "test", [])
      after
        Application.put_env(:aludel, :llm, original_config)
      end
    end

    test "returns error when API key is empty string" do
      original_config = Application.get_env(:aludel, :llm)
      Application.put_env(:aludel, :llm, anthropic_api_key: "")

      try do
        provider =
          provider_fixture(%{
            provider: :anthropic,
            model: "claude-3-5-sonnet-20241022",
            config: %{}
          })

        assert {:error, :missing_api_key} = LLM.call(provider, "test", [])
      after
        Application.put_env(:aludel, :llm, original_config)
      end
    end

    test "returns structured response" do
      mock_response = build_mock_response("Hello! I'm Claude.", 8, 6)

      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      provider =
        provider_fixture(%{
          provider: :anthropic,
          model: "claude-sonnet-4-6",
          config: %{"temperature" => 0.5, "max_tokens" => 100}
        })

      assert {:ok, result} = LLM.call(provider, "Say hello", [])
      assert is_binary(result.output)
      assert result.output != ""
      assert is_integer(result.input_tokens)
      assert result.input_tokens > 0
      assert is_integer(result.output_tokens)
      assert result.output_tokens > 0
      assert is_integer(result.latency_ms)
      assert is_float(result.cost_usd)
    end

    test "calculates cost for Anthropic" do
      mock_response = build_mock_response("Test response", 5, 10)

      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      provider =
        provider_fixture(%{
          provider: :anthropic,
          model: "claude-sonnet-4-6",
          config: %{}
        })

      {:ok, result} = LLM.call(provider, "test", [])
      assert result.cost_usd > 0
    end

    test "returns auth error for invalid API key" do
      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:error, %{status: 401}}
      end)

      provider =
        provider_fixture(%{
          provider: :anthropic,
          model: "claude-sonnet-4-6",
          config: %{}
        })

      result = LLM.call(provider, "test", [])

      assert {:error, {:auth_error, _message}} = result
    end

    test "returns invalid_request error for bad parameters" do
      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:error, %{status: 400}}
      end)

      provider =
        provider_fixture(%{
          provider: :anthropic,
          model: "invalid-model",
          config: %{}
        })

      result = LLM.call(provider, "test", [])

      assert {:error, {:invalid_request, _}} = result
    end
  end

  describe "call/3 with Ollama provider" do
    test "marks Ollama as an unauthenticated OpenAI-compatible backend" do
      mock_response = build_mock_response("Test response", 5, 10)

      expect(HttpClientMock, :request, fn model, _prompt, opts ->
        assert model == "openai:llama3.2"
        provider_options = Keyword.fetch!(opts, :provider_options)

        assert Keyword.fetch!(provider_options, :openai_compatible_backend) == :ollama
        refute Keyword.has_key?(opts, :api_key)

        {:ok, mock_response}
      end)

      provider =
        provider_fixture(%{
          provider: :ollama,
          model: "llama3.2",
          config: %{}
        })

      assert {:ok, _result} = LLM.call(provider, "test prompt", api_key: "ignored")
    end

    test "returns structured response" do
      mock_response = build_mock_response("Test response", 5, 10)

      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      provider =
        provider_fixture(%{
          provider: :ollama,
          model: "llama3.2",
          config: %{"temperature" => 0.8}
        })

      assert {:ok, result} = LLM.call(provider, "test prompt", [])
      assert is_binary(result.output)
      assert is_integer(result.input_tokens)
      assert is_integer(result.output_tokens)
      assert is_integer(result.latency_ms)
      assert is_float(result.cost_usd)
    end

    test "returns zero cost for Ollama (local)" do
      mock_response = build_mock_response("Test response", 5, 10)

      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      provider =
        provider_fixture(%{
          provider: :ollama,
          model: "llama3.2",
          config: %{}
        })

      {:ok, result} = LLM.call(provider, "test", [])
      assert result.cost_usd == 0.0
    end
  end

  describe "call/3 with Google provider" do
    test "returns structured response with all required fields" do
      mock_response = build_mock_response("Hello from Gemini!", 8, 6)

      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      provider =
        provider_fixture(%{
          provider: :google,
          model: "gemini-2.5-flash",
          config: %{"temperature" => 0.7}
        })

      assert {:ok, result} = LLM.call(provider, "test prompt", [])
      assert is_binary(result.output)
      assert result.output != ""
      assert is_integer(result.input_tokens)
      assert result.input_tokens > 0
      assert is_integer(result.output_tokens)
      assert result.output_tokens > 0
      assert is_integer(result.latency_ms)
      assert result.latency_ms >= 0
      assert is_float(result.cost_usd)
    end

    test "calculates cost for Google using LLMDB rates" do
      mock_response = build_mock_response("Test response", 5, 10)

      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      provider =
        provider_fixture(%{
          provider: :google,
          model: "gemini-2.5-flash",
          config: %{}
        })

      {:ok, result} = LLM.call(provider, "test", [])
      assert result.cost_usd > 0

      # gemini-2.5-flash LLMDB rates: input $0.30/1M, output $2.50/1M
      # mock response: 5 input tokens, 10 output tokens
      expected_cost = Float.round(5 * 0.3 / 1_000_000 + 10 * 2.5 / 1_000_000, 6)
      assert result.cost_usd == expected_cost
    end

    test "calls Google adapter successfully" do
      mock_response = build_mock_response("Hello!", 3, 2)

      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      provider =
        provider_fixture(%{
          provider: :google,
          model: "gemini-2.5-flash",
          config: %{"temperature" => 0.7, "max_tokens" => 100}
        })

      assert {:ok, result} = LLM.call(provider, "Say hello", [])
      assert is_binary(result.output)
      assert result.output != ""
      assert result.input_tokens > 0
      assert result.output_tokens > 0
    end

    test "returns error when API key is missing" do
      original_config = Application.get_env(:aludel, :llm)
      Application.put_env(:aludel, :llm, google_api_key: nil)

      try do
        provider =
          provider_fixture(%{
            provider: :google,
            model: "gemini-2.5-flash",
            config: %{}
          })

        assert {:error, :missing_api_key} = LLM.call(provider, "test", [])
      after
        Application.put_env(:aludel, :llm, original_config)
      end
    end

    test "returns error when API key is empty string" do
      original_config = Application.get_env(:aludel, :llm)
      Application.put_env(:aludel, :llm, google_api_key: "")

      try do
        provider =
          provider_fixture(%{
            provider: :google,
            model: "gemini-2.5-flash",
            config: %{}
          })

        assert {:error, :missing_api_key} = LLM.call(provider, "test", [])
      after
        Application.put_env(:aludel, :llm, original_config)
      end
    end

    test "returns auth error for invalid API key" do
      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:error, %{status: 401}}
      end)

      provider =
        provider_fixture(%{
          provider: :google,
          model: "gemini-2.5-flash",
          config: %{}
        })

      result = LLM.call(provider, "test", [])

      assert {:error, {:auth_error, _message}} = result
    end

    test "returns invalid_request error for bad parameters" do
      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:error, %{status: 400}}
      end)

      provider =
        provider_fixture(%{
          provider: :google,
          model: "invalid-model-name",
          config: %{}
        })

      result = LLM.call(provider, "test", [])

      assert {:error, {:invalid_request, _}} = result
    end

    test "returns rate_limit error" do
      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:error, %{status: 429}}
      end)

      provider =
        provider_fixture(%{
          provider: :google,
          model: "gemini-2.5-flash",
          config: %{}
        })

      result = LLM.call(provider, "test", [])

      assert {:error, {:rate_limit, nil}} = result
    end
  end

  describe "call/3 error handling" do
    test "returns missing_api_key when :llm config is entirely absent" do
      original_config = Application.get_env(:aludel, :llm)
      Application.delete_env(:aludel, :llm)

      try do
        for provider_type <- [:openai, :anthropic, :google] do
          provider =
            provider_fixture(%{provider: provider_type, model: "test-model", config: %{}})

          assert {:error, :missing_api_key} = LLM.call(provider, "test", [])
        end
      after
        Application.put_env(:aludel, :llm, original_config)
      end
    end

    test "handles network errors gracefully" do
      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:error, :timeout}
      end)

      provider =
        provider_fixture(%{
          provider: :openai,
          model: "gpt-4o",
          config: %{}
        })

      result = LLM.call(provider, "test", [])
      assert {:error, {:network_error, :timeout}} = result
    end
  end

  describe "call/3 token counting" do
    test "counts tokens for input and output" do
      mock_response = build_mock_response("Response", 10, 15)

      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      provider =
        provider_fixture(%{
          provider: :openai,
          model: "gpt-4o",
          config: %{}
        })

      {:ok, result} = LLM.call(provider, "Hello world", [])
      assert result.input_tokens > 0
      assert result.output_tokens > 0
    end
  end

  describe "call/3 latency measurement" do
    test "measures execution time in milliseconds" do
      mock_response = build_mock_response("Response", 5, 5)

      expect(HttpClientMock, :request, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      provider =
        provider_fixture(%{
          provider: :ollama,
          model: "llama3.2",
          config: %{}
        })

      {:ok, result} = LLM.call(provider, "test", [])
      assert result.latency_ms >= 0
      assert is_integer(result.latency_ms)
    end
  end

  describe "call/3 with documents option" do
    test "forwards documents to HTTP adapter" do
      mock_response = build_mock_response("The image is red", 100, 20)

      # Sample 1x1 red PNG
      image_data =
        Base.decode64!(
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="
        )

      document = %{data: image_data, content_type: "image/png"}

      expect(HttpClientMock, :request, fn _model, _prompt, opts ->
        # Verify documents are forwarded to adapter
        assert Keyword.has_key?(opts, :documents)
        assert opts[:documents] == [document]
        {:ok, mock_response}
      end)

      provider =
        provider_fixture(%{
          provider: :openai,
          model: "gpt-4o",
          config: %{"api_key" => "sk-test-key"}
        })

      assert {:ok, result} =
               LLM.call(provider, "What color is this image?", documents: [document])

      assert is_binary(result.output)
      assert result.output == "The image is red"
      assert result.input_tokens == 100
      assert result.output_tokens == 20
    end
  end

  defp build_mock_response(text, input_tokens, output_tokens) do
    %{
      content: text,
      input_tokens: input_tokens,
      output_tokens: output_tokens
    }
  end
end
