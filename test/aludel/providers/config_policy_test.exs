defmodule Aludel.Providers.ConfigPolicyTest do
  use ExUnit.Case, async: true

  alias Aludel.Providers.ConfigPolicy

  test "detects normalized credential keys recursively" do
    configs = [
      %{"API KEY" => "value"},
      %{"openai-api-key" => "value"},
      %{"headers" => [%{"Authorization" => "value"}]},
      %{"nested" => %{:client_secret => nil}},
      %{"api_secret" => "value"},
      %{"proxy_authorization" => "value"},
      %{"secret_key" => "value"},
      %{"aws_session_token" => "value"},
      [safe: true, api_secret: "value"]
    ]

    for config <- configs do
      assert {:error, :credentials_not_allowed} = ConfigPolicy.validate(config)
    end
  end

  test "sanitizes credential keys while preserving safe structure" do
    config = %{
      "api_key" => "top-level-value",
      "max_tokens" => 1_000,
      "nested" => [
        %{"Authorization" => "nested-value", "top_p" => 0.9},
        "unchanged"
      ]
    }

    assert ConfigPolicy.sanitize(config) == %{
             "max_tokens" => 1_000,
             "nested" => [%{"top_p" => 0.9}, "unchanged"]
           }
  end

  test "sanitizes credential entries from keyword lists" do
    config = [temperature: 0.2, headers: [proxy_authorization: "value"]]

    assert ConfigPolicy.sanitize(config) == [temperature: 0.2, headers: []]
  end

  test "allows safe token-related keys" do
    config = %{
      "max_tokens" => 1_000,
      "tokenizer" => "provider-default",
      "token_usage" => true
    }

    assert :ok = ConfigPolicy.validate(config)
    assert ConfigPolicy.sanitize(config) == config
  end
end
