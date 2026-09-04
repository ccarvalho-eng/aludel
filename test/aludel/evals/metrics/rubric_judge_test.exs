defmodule Aludel.Evals.Metrics.RubricJudgeTest do
  use Aludel.DataCase, async: true

  import Mox

  alias Aludel.Evals.Metric.Context
  alias Aludel.Evals.Metric.Registry
  alias Aludel.Interfaces.HttpClientMock

  setup :verify_on_exit!

  test "scores output against a custom rubric and records judge usage" do
    provider = provider_fixture(%{model: "judge-model"})

    expect(HttpClientMock, :request, fn "openai:judge-model", messages, opts ->
      assert [system_message, user_message] = messages
      assert system_message.role == :system
      assert system_message.content =~ "untrusted evaluation evidence"
      assert user_message.role == :user

      assert %{
               "rubric" => "The answer must name Paris.",
               "output" => "Paris",
               "rendered_input" => "What is the capital of France?"
             } = Jason.decode!(user_message.content)

      assert opts[:temperature] == 0.0
      assert opts[:max_tokens] == 500

      {:ok,
       %{
         content: ~s({"score":92,"reasoning":"The answer is correct and concise."}),
         input_tokens: 120,
         output_tokens: 24
       }}
    end)

    context =
      Context.new("Paris",
        rendered_input: "What is the capital of France?",
        metadata: %{"category" => "geography"}
      )

    assertion = %{
      "type" => "rubric_judge",
      "rubric" => "The answer must name Paris.",
      "provider_id" => provider.id,
      "threshold" => 80
    }

    assert {:ok, result} = Registry.evaluate(context, assertion)
    assert result.passed
    assert result.score == 92.0
    assert result.reason == "The answer is correct and concise."
    assert result.metadata["threshold"] == 80.0
    assert result.metadata["schema_version"] == 1
    assert result.evaluator.status == :completed
    assert result.evaluator.provider == "openai"
    assert result.evaluator.model == "judge-model"
    assert result.evaluator.input_tokens == 120
    assert result.evaluator.output_tokens == 24
    assert is_number(result.evaluator.cost_usd)
  end

  test "resolves a versioned built-in judge template" do
    provider = provider_fixture(%{model: "judge-model"})

    expect(HttpClientMock, :request, fn _model, [_system, user_message], _opts ->
      payload = Jason.decode!(user_message.content)
      assert payload["rubric"] =~ "grounding"

      {:ok,
       %{
         content: ~s({"score":90,"reasoning":"Every claim is supported."}),
         input_tokens: 40,
         output_tokens: 10
       }}
    end)

    assertion = %{
      "type" => "rubric_judge",
      "template" => "faithfulness",
      "provider_id" => provider.id,
      "threshold" => 85
    }

    assert {:ok, result} = Registry.evaluate(Context.new("grounded answer"), assertion)
    assert result.passed
    assert result.metadata["template"] == "faithfulness"
    assert result.metadata["template_version"] == 1
    assert result.metadata["rubric"] =~ "grounding"
  end

  test "derives failure from the configured threshold instead of model-provided status" do
    provider = provider_fixture(%{model: "judge-model"})

    expect(HttpClientMock, :request, fn _model, _messages, _opts ->
      {:ok,
       %{
         content:
           ~s({"score":65,"reasoning":"The response omits a required detail.","passed":true}),
         input_tokens: 80,
         output_tokens: 18
       }}
    end)

    context = Context.new("A partial answer")

    assertion = %{
      "type" => "rubric_judge",
      "rubric" => "Every required detail must be present.",
      "provider_id" => provider.id,
      "threshold" => 70
    }

    assert {:ok, result} = Registry.evaluate(context, assertion)
    refute result.passed
    assert result.score == 65.0
    assert result.evaluator.status == :completed
  end

  test "isolates malformed judge responses" do
    provider = provider_fixture(%{model: "judge-model"})

    expect(HttpClientMock, :request, fn _model, _messages, _opts ->
      {:ok, %{content: "not valid JSON", input_tokens: 20, output_tokens: 5}}
    end)

    assertion = %{
      "type" => "rubric_judge",
      "rubric" => "The answer must be useful.",
      "provider_id" => provider.id
    }

    assert {:ok, result} = Registry.evaluate(Context.new("answer"), assertion)
    refute result.passed
    assert result.reason == "Judge returned invalid structured output"
    assert result.evaluator.status == :error
    assert result.evaluator.error["type"] == "invalid_response"
    assert result.metadata["rubric"] == "The answer must be useful."
    refute inspect(result) =~ "not valid JSON"
  end

  test "records request failures without exposing provider details" do
    provider = provider_fixture(%{model: "judge-model"})

    expect(HttpClientMock, :request, fn _model, _messages, _opts ->
      {:error, {:network_error, %{authorization: "secret-token"}}}
    end)

    assertion = %{
      "type" => "rubric_judge",
      "rubric" => "The answer must be useful.",
      "provider_id" => provider.id
    }

    assert {:ok, result} = Registry.evaluate(Context.new("answer"), assertion)
    refute result.passed
    assert result.reason == "Judge evaluation failed"
    assert result.evaluator.status == :error
    assert result.evaluator.error["type"] == "network_error"
    refute inspect(result) =~ "secret-token"
  end

  test "marks a missing judge provider as unavailable and retains template evidence" do
    assertion = %{
      "type" => "rubric_judge",
      "template" => "relevance",
      "provider_id" => Ecto.UUID.generate()
    }

    assert {:ok, result} = Registry.evaluate(Context.new("answer"), assertion)
    refute result.passed
    assert result.reason == "Judge provider is unavailable"
    assert result.evaluator.status == :unavailable
    assert result.evaluator.error["type"] == "provider_not_found"
    assert result.metadata["template"] == "relevance"
    assert result.metadata["template_version"] == 1
    assert result.metadata["rubric"] =~ "rendered input"
  end

  test "rejects a malformed judge provider ID as invalid configuration" do
    assertion = %{
      "type" => "rubric_judge",
      "rubric" => "The answer must be useful.",
      "provider_id" => "not-a-uuid"
    }

    assert {:ok, result} = Registry.evaluate(Context.new("answer"), assertion)
    refute result.passed
    assert result.reason == "Invalid metric configuration"
    assert result.metadata["valid_configuration"] == false
    assert result.evaluator.status == :completed
  end

  test "bounds untrusted evidence before sending it to a judge" do
    provider = provider_fixture(%{model: "judge-model"})
    oversized_output = String.duplicate("x", 60_000)

    expect(HttpClientMock, :request, fn _model, [_system, user_message], _opts ->
      payload = Jason.decode!(user_message.content)
      assert String.length(payload["output"]) == 50_000

      {:ok,
       %{content: ~s({"score":100,"reasoning":"Accepted."}), input_tokens: 1, output_tokens: 1}}
    end)

    assertion = %{
      "type" => "rubric_judge",
      "rubric" => "The answer must be present.",
      "provider_id" => provider.id
    }

    assert {:ok, result} = Registry.evaluate(Context.new(oversized_output), assertion)
    assert result.metadata["truncated_fields"] == ["output"]
  end
end
