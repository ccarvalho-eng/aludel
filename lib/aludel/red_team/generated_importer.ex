defmodule Aludel.RedTeam.GeneratedImporter do
  @moduledoc false

  alias Aludel.Datasets.Dataset
  alias Aludel.RedTeam.DatasetImporter
  alias Aludel.RedTeam.Generation
  alias Aludel.RedTeam.Generator

  @default_variable "input"
  @default_judge_threshold 80

  @spec import(Dataset.t(), Generation.t(), keyword()) ::
          {:ok, DatasetImporter.result()} | {:error, term()}
  def import(%Dataset{} = dataset, %Generation{} = generation, opts) when is_list(opts) do
    with true <- Generator.valid?(generation),
         {:ok, dataset_id} <- validate_dataset_id(dataset.id),
         {:ok, normalized} <- validate_options(generation, opts),
         {:ok, selected} <- select_approved_cases(generation.cases, normalized) do
      prepared_entries = Enum.map(selected, &prepare_entry(&1, generation, normalized))
      DatasetImporter.persist(dataset_id, prepared_entries)
    else
      false -> {:error, :invalid_generation}
      {:error, _reason} = error -> error
    end
  end

  def import(%Dataset{}, %Generation{}, _opts) do
    {:error, :invalid_options}
  end

  def import(%Dataset{}, _generation, _opts) do
    {:error, :invalid_generation}
  end

  def import(_dataset, _generation, _opts) do
    {:error, :dataset_not_found}
  end

  defp validate_options(generation, opts) do
    defaults = [
      approved_case_ids: [],
      variable: @default_variable,
      judge_provider_id: generation.provider.id,
      judge_threshold: @default_judge_threshold
    ]

    if Keyword.keyword?(opts) do
      case Keyword.validate(opts, defaults) do
        {:ok, normalized} -> validate_normalized_options(normalized)
        {:error, _unknown} -> {:error, :invalid_options}
      end
    else
      {:error, :invalid_options}
    end
  end

  defp validate_normalized_options(opts) do
    with :ok <- validate_approved_case_ids(opts[:approved_case_ids]),
         :ok <- validate_variable(opts[:variable]),
         :ok <- validate_judge_provider_id(opts[:judge_provider_id]),
         :ok <- validate_judge_threshold(opts[:judge_threshold]) do
      {:ok, opts}
    end
  end

  defp validate_approved_case_ids(case_ids) when is_list(case_ids) and case_ids != [] do
    if Enum.all?(case_ids, &is_binary/1) and Enum.uniq(case_ids) == case_ids do
      :ok
    else
      {:error, :invalid_approved_case_ids}
    end
  end

  defp validate_approved_case_ids(_case_ids) do
    {:error, :invalid_approved_case_ids}
  end

  defp validate_variable(variable) when is_binary(variable) do
    if String.valid?(variable) and
         byte_size(variable) <= 200 and
         Regex.match?(~r/\A[a-zA-Z_][a-zA-Z0-9_.-]*\z/u, variable) do
      :ok
    else
      {:error, :invalid_variable}
    end
  end

  defp validate_variable(_variable) do
    {:error, :invalid_variable}
  end

  defp validate_judge_provider_id(provider_id) when is_binary(provider_id) do
    case Ecto.UUID.cast(provider_id) do
      {:ok, _provider_id} -> :ok
      :error -> {:error, :invalid_judge_provider_id}
    end
  end

  defp validate_judge_provider_id(_provider_id) do
    {:error, :invalid_judge_provider_id}
  end

  defp validate_judge_threshold(threshold)
       when is_number(threshold) and threshold >= 0 and threshold <= 100 do
    :ok
  end

  defp validate_judge_threshold(_threshold) do
    {:error, :invalid_judge_threshold}
  end

  defp validate_dataset_id(dataset_id) do
    case Ecto.UUID.cast(dataset_id) do
      {:ok, normalized_id} -> {:ok, normalized_id}
      :error -> {:error, :dataset_not_found}
    end
  end

  defp select_approved_cases(cases, opts) do
    approved_ids = opts[:approved_case_ids]
    known_ids = Enum.map(cases, & &1.id)

    case Enum.reject(approved_ids, &(&1 in known_ids)) do
      [] -> {:ok, Enum.filter(cases, &(&1.id in approved_ids))}
      unknown -> {:error, {:unknown_case_ids, unknown}}
    end
  end

  defp prepare_entry(generated_case, generation, opts) do
    variable = opts[:variable]
    deduplication_key = deduplication_key(generated_case, generation, variable)

    %{
      deduplication_key: deduplication_key,
      attrs: %{
        name: generated_case.name,
        variable_values: %{variable => generated_case.prompt},
        assertions: [judge_assertion(generated_case, opts)],
        metadata: metadata(generated_case, generation, variable, deduplication_key, opts)
      }
    }
  end

  defp judge_assertion(generated_case, opts) do
    %{
      "type" => "rubric_judge",
      "template" => generated_case.recommended_judge,
      "provider_id" => opts[:judge_provider_id],
      "threshold" => opts[:judge_threshold]
    }
  end

  defp metadata(generated_case, generation, variable, deduplication_key, opts) do
    %{
      "red_team" => %{
        "source" => "generated",
        "case_id" => generated_case.id,
        "case_checksum" => generated_case.checksum,
        "category" => Atom.to_string(generated_case.category),
        "severity" => Atom.to_string(generated_case.severity),
        "technique" => Atom.to_string(generated_case.technique),
        "rationale" => generated_case.rationale,
        "recommended_judge" => generated_case.recommended_judge,
        "generation_id" => generation.id,
        "generation_checksum" => generation.checksum,
        "generation_schema_version" => generation.schema_version,
        "generation_prompt_version" => generation.prompt_version,
        "generation_status" => Atom.to_string(generation.status),
        "generated_at" => DateTime.to_iso8601(generation.generated_at),
        "requested_categories" => Enum.map(generation.requested_categories, &Atom.to_string/1),
        "generator" => stringify_map(generation.provider),
        "generation_usage" => stringify_map(generation.usage),
        "generation_limits" => stringify_map(generation.limits),
        "generation_failures" => Enum.map(generation.failures, &stringify_failure/1),
        "target_context_checksum" => generation.target_context_checksum,
        "review" => %{"approved" => true, "case_id" => generated_case.id},
        "checksum" => import_checksum(generated_case, generation, variable, opts),
        "deduplication_key" => deduplication_key,
        "provenance" => %{
          "source" => "Aludel generated red-team review",
          "generation_id" => generation.id,
          "case_id" => generated_case.id
        }
      }
    }
  end

  defp stringify_failure(failure) do
    %{
      "category" => Atom.to_string(failure.category),
      "type" => Atom.to_string(failure.type),
      "message" => failure.message
    }
  end

  defp stringify_map(map) do
    Map.new(map, fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp import_checksum(generated_case, generation, variable, opts) do
    [
      generation.checksum,
      generated_case.checksum,
      variable,
      opts[:judge_provider_id],
      to_string(opts[:judge_threshold])
    ]
    |> Enum.join("\u0000")
    |> sha256()
  end

  defp deduplication_key(generated_case, generation, variable) do
    "aludel:red_team:generated@#{generation.schema_version}:#{generation.id}:#{generated_case.id}:#{variable}"
    |> DatasetImporter.bounded_key()
  end

  defp sha256(value) do
    value
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
