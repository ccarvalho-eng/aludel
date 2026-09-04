defmodule Aludel.RedTeam.GeneratedCase do
  @moduledoc """
  A validated, reviewable adversarial case proposed by a generator model.

  Generated cases are inert values. Generation does not persist or execute
  them; callers review the fields before creating any evaluation data.
  """

  alias Aludel.Evals.JudgeCatalog
  alias Aludel.RedTeam.Catalog

  @enforce_keys [
    :id,
    :category,
    :name,
    :prompt,
    :severity,
    :technique,
    :rationale,
    :recommended_judge,
    :checksum
  ]

  defstruct @enforce_keys

  @severities %{"medium" => :medium, "high" => :high, "critical" => :critical}
  @techniques %{"direct" => :direct, "indirect" => :indirect}
  @response_keys ~w(name prompt rationale recommended_judge severity technique)
  @checksum_version 1
  @max_name_chars 200
  @max_prompt_chars 10_000
  @max_rationale_chars 2_000

  @type severity :: :medium | :high | :critical
  @type technique :: :direct | :indirect

  @type t :: %__MODULE__{
          id: String.t(),
          category: Aludel.RedTeam.Catalog.category(),
          name: String.t(),
          prompt: String.t(),
          severity: severity(),
          technique: technique(),
          rationale: String.t(),
          recommended_judge: String.t(),
          checksum: String.t()
        }

  @doc false
  @spec new(Aludel.RedTeam.Catalog.category(), map()) :: {:ok, t()} | :error
  def new(category, attrs) when is_atom(category) and is_map(attrs) do
    with true <- category in Catalog.categories(),
         true <- Map.keys(attrs) |> Enum.sort() == @response_keys,
         {:ok, name} <- bounded_text(attrs["name"], @max_name_chars),
         {:ok, prompt} <- bounded_text(attrs["prompt"], @max_prompt_chars, trim: false),
         {:ok, rationale} <- bounded_text(attrs["rationale"], @max_rationale_chars),
         {:ok, severity} <- Map.fetch(@severities, attrs["severity"]),
         {:ok, technique} <- Map.fetch(@techniques, attrs["technique"]),
         true <- attrs["recommended_judge"] in JudgeCatalog.ids() do
      fields = %{
        category: category,
        name: name,
        prompt: prompt,
        severity: severity,
        technique: technique,
        rationale: rationale,
        recommended_judge: attrs["recommended_judge"]
      }

      checksum = checksum(fields)

      {:ok,
       struct!(
         __MODULE__,
         Map.merge(fields, %{
           id: generated_id(category, checksum),
           checksum: checksum
         })
       )}
    else
      _invalid -> :error
    end
  end

  def new(_category, _attrs) do
    :error
  end

  @doc false
  @spec valid?(t()) :: boolean()
  def valid?(
        %__MODULE__{severity: severity, technique: technique, category: category} = generated_case
      )
      when severity in [:medium, :high, :critical] and technique in [:direct, :indirect] and
             is_atom(category) do
    attrs = %{
      "name" => generated_case.name,
      "prompt" => generated_case.prompt,
      "severity" => Atom.to_string(generated_case.severity),
      "technique" => Atom.to_string(generated_case.technique),
      "rationale" => generated_case.rationale,
      "recommended_judge" => generated_case.recommended_judge
    }

    case new(generated_case.category, attrs) do
      {:ok, rebuilt} -> rebuilt == generated_case
      :error -> false
    end
  end

  def valid?(_generated_case) do
    false
  end

  defp bounded_text(value, max_chars, opts \\ []) do
    trim? = Keyword.get(opts, :trim, true)

    if is_binary(value) and String.valid?(value) and not String.contains?(value, "\u0000") do
      normalized = if trim?, do: String.trim(value), else: value

      if String.trim(normalized) != "" and String.length(normalized) <= max_chars do
        {:ok, normalized}
      else
        :error
      end
    else
      :error
    end
  end

  defp checksum(fields) do
    [
      Integer.to_string(@checksum_version),
      Atom.to_string(fields.category),
      fields.name,
      fields.prompt,
      Atom.to_string(fields.severity),
      Atom.to_string(fields.technique),
      fields.rationale,
      fields.recommended_judge
    ]
    |> Enum.join("\u0000")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp generated_id(category, checksum) do
    category = category |> Atom.to_string() |> String.replace("_", "-")
    "#{category}-#{String.slice(checksum, 0, 16)}"
  end
end
