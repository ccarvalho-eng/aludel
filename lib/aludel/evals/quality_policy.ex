defmodule Aludel.Evals.QualityPolicy do
  @moduledoc """
  Validates and evaluates versioned suite quality policies.

  Policies combine pass-rate, metadata-group, evaluator-score, cost, and
  latency rules. Evaluation returns explicit `passed`, `failed`, `invalid`, or
  `unavailable` status without conflating missing evidence with a quality
  failure.
  """

  @schema_version 1
  @max_rules 50
  @max_definition_bytes 100_000
  @rule_types [
    "overall_pass_rate",
    "metadata_pass_rate",
    "evaluator_score",
    "total_cost_usd",
    "average_latency_ms"
  ]

  @type definition :: %{required(String.t()) => term()}
  @type evaluation :: %{required(String.t()) => term()}

  @doc """
  Validates a version-one policy definition.

  A policy must be JSON-compatible, cannot exceed #{@max_definition_bytes}
  encoded bytes, and must contain between one and #{@max_rules} field-strict
  rules with unique IDs. Pass rates use values from `0.0` through `1.0`,
  evaluator scores use values from `0` through `100`, and budget maximums must
  be non-negative.
  """
  @spec validate(term()) :: :ok | {:error, [String.t()]}
  def validate(definition) do
    errors = definition_errors(definition)

    if errors == [] do
      :ok
    else
      {:error, errors}
    end
  end

  @doc """
  Evaluates a policy against persisted test case results and suite aggregates.

  Missing test cases, matching metadata groups, evaluator scores, cost, or
  latency produce an `unavailable` rule instead of silently passing or failing.
  Malformed definitions produce an `invalid` policy result.
  """
  @spec evaluate(term(), [map()], map()) :: evaluation()
  def evaluate(definition, results, summary) when is_list(results) and is_map(summary) do
    with :ok <- validate(definition),
         true <- Enum.all?(results, &is_map/1) do
      evaluate_rules(definition["rules"], results, summary)
    else
      {:error, errors} -> invalid_evaluation(errors)
      false -> invalid_evaluation(["results must contain only maps"])
    end
  end

  def evaluate(definition, _results, _summary) do
    errors =
      case validate(definition) do
        :ok -> ["results must be a list and summary must be a map"]
        {:error, definition_errors} -> definition_errors
      end

    invalid_evaluation(errors)
  end

  defp definition_errors(definition) when is_map(definition) do
    encoding_errors = encoding_errors(definition)

    field_errors =
      if Map.keys(definition) -- ["schema_version", "rules"] == [] do
        []
      else
        ["policy contains unsupported fields"]
      end

    schema_errors =
      if definition["schema_version"] == @schema_version do
        []
      else
        ["schema_version must be #{@schema_version}"]
      end

    rules = definition["rules"]

    rules_errors =
      if is_list(rules) and length(rules) in 1..@max_rules do
        rules
        |> Enum.with_index()
        |> Enum.flat_map(fn {rule, index} -> rule_errors(rule, index) end)
        |> Kernel.++(duplicate_id_errors(rules))
      else
        ["rules must contain between 1 and #{@max_rules} entries"]
      end

    encoding_errors ++ field_errors ++ schema_errors ++ rules_errors
  end

  defp definition_errors(_definition) do
    ["policy must be a map"]
  end

  defp rule_errors(rule, index) when is_map(rule) do
    rule_id_errors(rule, index) ++
      rule_type_errors(rule, index) ++
      rule_field_errors(rule, index) ++ rule_configuration_errors(rule, index)
  end

  defp rule_errors(_rule, index) do
    ["rules[#{index}] must be a map"]
  end

  defp rule_id_errors(%{"id" => id}, index) when is_binary(id) and byte_size(id) <= 100 do
    if String.trim(id) == "" do
      ["rules[#{index}].id must be a non-empty string up to 100 bytes"]
    else
      []
    end
  end

  defp rule_id_errors(_rule, index) do
    ["rules[#{index}].id must be a non-empty string up to 100 bytes"]
  end

  defp rule_type_errors(%{"type" => type}, _index) when type in @rule_types do
    []
  end

  defp rule_type_errors(_rule, index) do
    ["rules[#{index}].type is not supported"]
  end

  defp rule_field_errors(%{"type" => type} = rule, index) when type in @rule_types do
    allowed_fields =
      case type do
        "overall_pass_rate" -> ["id", "type", "minimum"]
        "metadata_pass_rate" -> ["id", "type", "metadata", "minimum"]
        "evaluator_score" -> ["id", "type", "metric", "minimum"]
        _budget -> ["id", "type", "maximum"]
      end

    if Map.keys(rule) -- allowed_fields == [] do
      []
    else
      ["rules[#{index}] contains unsupported fields"]
    end
  end

  defp rule_field_errors(_rule, _index) do
    []
  end

  defp rule_configuration_errors(%{"type" => "overall_pass_rate"} = rule, index) do
    minimum_rate_errors(rule, index)
  end

  defp rule_configuration_errors(%{"type" => "metadata_pass_rate"} = rule, index) do
    metadata_errors(rule, index) ++ minimum_rate_errors(rule, index)
  end

  defp rule_configuration_errors(%{"type" => "evaluator_score"} = rule, index) do
    metric_errors(rule, index) ++ score_errors(rule, index)
  end

  defp rule_configuration_errors(%{"type" => type} = rule, index)
       when type in ["total_cost_usd", "average_latency_ms"] do
    maximum_errors(rule, index)
  end

  defp rule_configuration_errors(_rule, _index) do
    []
  end

  defp minimum_rate_errors(%{"minimum" => minimum}, _index)
       when is_number(minimum) and minimum >= 0 and minimum <= 1 do
    []
  end

  defp minimum_rate_errors(_rule, index) do
    ["rules[#{index}].minimum must be a number between 0 and 1"]
  end

  defp score_errors(%{"minimum" => minimum}, _index)
       when is_number(minimum) and minimum >= 0 and minimum <= 100 do
    []
  end

  defp score_errors(_rule, index) do
    ["rules[#{index}].minimum must be a number between 0 and 100"]
  end

  defp maximum_errors(%{"maximum" => maximum}, _index)
       when is_number(maximum) and maximum >= 0 do
    []
  end

  defp maximum_errors(_rule, index) do
    ["rules[#{index}].maximum must be a non-negative number"]
  end

  defp metadata_errors(%{"metadata" => metadata}, _index)
       when is_map(metadata) and map_size(metadata) > 0 do
    []
  end

  defp metadata_errors(_rule, index) do
    ["rules[#{index}].metadata must be a non-empty map"]
  end

  defp metric_errors(%{"metric" => metric}, index)
       when is_binary(metric) and byte_size(metric) <= 100 do
    if String.trim(metric) == "" do
      ["rules[#{index}].metric must be a non-empty string up to 100 bytes"]
    else
      []
    end
  end

  defp metric_errors(_rule, index) do
    ["rules[#{index}].metric must be a non-empty string up to 100 bytes"]
  end

  defp duplicate_id_errors(rules) do
    duplicate? =
      rules
      |> Enum.map(fn
        %{"id" => id} when is_binary(id) -> id
        _rule -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()
      |> Enum.any?(fn {_id, count} -> count > 1 end)

    if duplicate?, do: ["rule ids must be unique"], else: []
  end

  defp encoding_errors(definition) do
    case Jason.encode(definition) do
      {:ok, encoded} when byte_size(encoded) <= @max_definition_bytes ->
        []

      {:ok, _encoded} ->
        ["policy cannot exceed #{@max_definition_bytes} encoded bytes"]

      {:error, _reason} ->
        ["policy must contain only JSON-compatible values"]
    end
  end

  defp evaluate_rules(rules, results, summary) do
    rule_results = Enum.map(rules, &evaluate_rule(&1, results, summary))
    status = overall_status(rule_results)

    %{
      "schema_version" => @schema_version,
      "status" => status,
      "passed" => status == "passed",
      "rules" => rule_results
    }
  end

  defp evaluate_rule(%{"type" => "overall_pass_rate"} = rule, results, _summary) do
    rate_rule(rule, results, "No test case results were available")
  end

  defp evaluate_rule(%{"type" => "metadata_pass_rate"} = rule, results, _summary) do
    matching_results =
      Enum.filter(results, fn result ->
        metadata_matches?(result["test_case_metadata"], rule["metadata"])
      end)

    rate_rule(rule, matching_results, "No test cases matched the metadata group")
  end

  defp evaluate_rule(%{"type" => "evaluator_score"} = rule, results, _summary) do
    scores = evaluator_scores(results, rule["metric"])

    case average(scores) do
      nil -> unavailable_rule(rule, "No completed evaluator scores were available")
      actual -> minimum_rule(rule, actual, length(scores))
    end
  end

  defp evaluate_rule(%{"type" => "total_cost_usd"} = rule, _results, summary) do
    case normalize_number(summary_value(summary, :total_cost_usd)) do
      nil -> unavailable_rule(rule, "Total cost was unavailable")
      actual -> maximum_rule(rule, actual)
    end
  end

  defp evaluate_rule(%{"type" => "average_latency_ms"} = rule, _results, summary) do
    case normalize_number(summary_value(summary, :avg_latency_ms)) do
      nil -> unavailable_rule(rule, "Average latency was unavailable")
      actual -> maximum_rule(rule, actual)
    end
  end

  defp rate_rule(rule, [], reason) do
    unavailable_rule(rule, reason)
  end

  defp rate_rule(rule, results, _reason) do
    passed = Enum.count(results, &(&1["passed"] == true))
    actual = passed / length(results)
    minimum_rule(rule, actual, length(results))
  end

  defp minimum_rule(rule, actual, sample_count) do
    passed = actual >= rule["minimum"]

    rule
    |> Map.take(["id", "type", "minimum", "metadata", "metric"])
    |> Map.merge(%{
      "status" => status(passed),
      "passed" => passed,
      "actual" => displayed_actual(rule["type"], actual),
      "sample_count" => sample_count
    })
  end

  defp maximum_rule(rule, actual) do
    passed = actual <= rule["maximum"]

    rule
    |> Map.take(["id", "type", "maximum"])
    |> Map.merge(%{"status" => status(passed), "passed" => passed, "actual" => actual})
  end

  defp unavailable_rule(rule, reason) do
    rule
    |> Map.take(["id", "type", "minimum", "maximum", "metadata", "metric"])
    |> Map.merge(%{
      "status" => "unavailable",
      "passed" => false,
      "actual" => nil,
      "sample_count" => 0,
      "reason" => reason
    })
  end

  defp evaluator_scores(results, metric) do
    results
    |> Enum.flat_map(&attempt_results/1)
    |> Enum.flat_map(&assertion_results/1)
    |> Enum.filter(&completed_metric?(&1, metric))
    |> Enum.map(& &1["score"])
    |> Enum.filter(&is_number/1)
  end

  defp attempt_results(%{"attempts" => attempts}) when is_list(attempts) and attempts != [] do
    attempts
  end

  defp attempt_results(result) do
    [result]
  end

  defp assertion_results(%{"assertion_results" => results}) when is_list(results) do
    results
  end

  defp assertion_results(_result) do
    []
  end

  defp completed_metric?(%{"type" => metric, "evaluator" => %{"status" => status}}, metric) do
    status == "completed"
  end

  defp completed_metric?(%{"type" => metric, "evaluator" => nil}, metric) do
    true
  end

  defp completed_metric?(%{"type" => metric} = result, metric) do
    not Map.has_key?(result, "evaluator")
  end

  defp completed_metric?(_result, _metric) do
    false
  end

  defp metadata_matches?(metadata, matcher) when is_map(metadata) and is_map(matcher) do
    Enum.all?(matcher, fn {key, value} -> Map.get(metadata, key) == value end)
  end

  defp metadata_matches?(_metadata, _matcher) do
    false
  end

  defp summary_value(summary, key) do
    Map.get(summary, key, Map.get(summary, Atom.to_string(key)))
  end

  defp normalize_number(%Decimal{} = value) do
    Decimal.to_float(value)
  end

  defp normalize_number(value) when is_number(value) do
    value
  end

  defp normalize_number(_value) do
    nil
  end

  defp average([]) do
    nil
  end

  defp average(values) do
    Enum.sum(values) / length(values)
  end

  defp displayed_actual(type, actual)
       when type in ["overall_pass_rate", "metadata_pass_rate"] do
    Float.round(actual, 4)
  end

  defp displayed_actual("evaluator_score", actual) do
    Float.round(actual, 1)
  end

  defp overall_status(rule_results) do
    statuses = Enum.map(rule_results, & &1["status"])

    cond do
      "unavailable" in statuses -> "unavailable"
      "failed" in statuses -> "failed"
      true -> "passed"
    end
  end

  defp status(true) do
    "passed"
  end

  defp status(false) do
    "failed"
  end

  defp invalid_evaluation(errors) do
    %{
      "schema_version" => @schema_version,
      "status" => "invalid",
      "passed" => false,
      "rules" => [],
      "errors" => errors
    }
  end
end
