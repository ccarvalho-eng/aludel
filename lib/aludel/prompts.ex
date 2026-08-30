defmodule Aludel.Prompts do
  @moduledoc """
  Context for managing prompts and their versions.
  """

  import Ecto.Query

  alias Aludel.Prompts.{Evolution, Prompt, PromptVersion}
  alias Ecto.Changeset
  alias Ecto.Multi

  @doc """
  Lists all prompts in the system.

  When called without params, returns all prompts as a list.
  When called with filter params, returns the filtered prompt list.

  ## Options

    * `:search` - Case-insensitive search applied to prompt name and description
    * `:tags` - Filter by any matching prompt tag
    * `:project_id` - Filter by project ID

  """
  @spec list_prompts() :: [Prompt.t()]
  def list_prompts do
    repo().all(Prompt)
  end

  @spec list_prompts(map()) :: [Prompt.t()]
  def list_prompts(params) when is_map(params) do
    search = normalize_search(Map.get(params, :search))
    tags = normalize_tags(Map.get(params, :tags, []))
    project_id = normalize_project_id(Map.get(params, :project_id))

    Prompt
    |> order_by([p], desc: p.inserted_at)
    |> maybe_filter_by_search(search)
    |> maybe_filter_by_tags(tags)
    |> maybe_filter_by_project_id(project_id)
    |> repo().all()
  end

  @doc """
  Lists all prompts with their versions preloaded.

  Versions are ordered by version number descending.
  """
  @spec list_prompts_with_versions() :: [Prompt.t()]
  def list_prompts_with_versions do
    query =
      from(p in Prompt,
        preload: [versions: ^from(v in PromptVersion, order_by: [desc: v.version])]
      )

    repo().all(query)
  end

  @doc """
  Gets a prompt by ID, raising if not found.
  """
  @spec get_prompt!(binary()) :: Prompt.t()
  def get_prompt!(id) do
    repo().get!(Prompt, id)
  end

  @doc """
  Gets a prompt with all versions preloaded, ordered by version
  descending.
  """
  @spec get_prompt_with_versions!(binary()) :: Prompt.t()
  def get_prompt_with_versions!(id) do
    query =
      from(p in Prompt,
        where: p.id == ^id,
        preload: [versions: ^from(v in PromptVersion, order_by: [desc: v.version])]
      )

    repo().one!(query)
  end

  @doc """
  Gets a prompt version by ID, raising if not found.

  Preloads the associated prompt.
  """
  @spec get_prompt_version!(binary()) :: PromptVersion.t()
  def get_prompt_version!(id) do
    PromptVersion
    |> repo().get!(id)
    |> repo().preload(:prompt)
  end

  @doc """
  Returns a changeset for tracking prompt changes.
  """
  @spec change_prompt(Prompt.t(), map()) :: Ecto.Changeset.t()
  def change_prompt(%Prompt{} = prompt, attrs \\ %{}) do
    Prompt.changeset(prompt, attrs)
  end

  @doc """
  Creates a new prompt.
  """
  @spec create_prompt(map()) ::
          {:ok, Prompt.t()} | {:error, Changeset.t()}
  def create_prompt(attrs \\ %{}) do
    %Prompt{}
    |> Prompt.changeset(attrs)
    |> repo().insert()
  end

  @doc """
  Creates a prompt and its initial version in a single transaction.

  Blank templates do not create an initial prompt version.
  """
  @spec create_prompt_with_initial_version(map()) ::
          {:ok, Prompt.t()} | {:error, Changeset.t()}
  def create_prompt_with_initial_version(attrs \\ %{}) do
    attrs = normalize_attrs(attrs)
    template = normalized_template(attrs)

    attrs
    |> create_prompt_multi(template)
    |> repo().transaction()
    |> case do
      {:ok, %{prompt: prompt}} ->
        {:ok, prompt}

      {:error, :prompt, %Changeset{} = changeset, _changes_so_far} ->
        {:error, changeset}

      {:error, :prompt_version, %Changeset{} = changeset, changes_so_far} ->
        {:error, prompt_version_error(changes_so_far[:prompt], attrs, changeset)}
    end
  end

  @doc """
  Updates an existing prompt.
  """
  @spec update_prompt(Prompt.t(), map()) ::
          {:ok, Prompt.t()} | {:error, Changeset.t()}
  def update_prompt(%Prompt{} = prompt, attrs) do
    prompt
    |> Prompt.changeset(attrs)
    |> repo().update()
  end

  @doc """
  Updates a prompt and creates a new version if the template changed.

  The prompt update and optional version creation run in a single transaction.
  """
  @spec update_prompt_with_optional_version(Prompt.t(), map()) ::
          {:ok, Prompt.t()} | {:error, Changeset.t()}
  def update_prompt_with_optional_version(%Prompt{} = prompt, attrs) do
    attrs = normalize_attrs(attrs)
    prompt = ensure_versions_loaded(prompt)
    new_template = normalized_template(attrs)
    latest_template = latest_template(prompt)

    prompt
    |> update_prompt_multi(
      attrs,
      if(new_template == "" or new_template == latest_template, do: "", else: new_template)
    )
    |> repo().transaction()
    |> case do
      {:ok, %{prompt: updated_prompt}} ->
        {:ok, updated_prompt}

      {:error, :prompt, %Changeset{} = changeset, _changes_so_far} ->
        {:error, changeset}

      {:error, :prompt_version, %Changeset{} = changeset, changes_so_far} ->
        {:error, prompt_version_error(changes_so_far[:prompt] || prompt, attrs, changeset)}
    end
  end

  @doc """
  Deletes a prompt.
  """
  @spec delete_prompt(Prompt.t()) ::
          {:ok, Prompt.t()} | {:error, Changeset.t()}
  def delete_prompt(%Prompt{} = prompt) do
    repo().delete(prompt)
  end

  @doc """
  Creates a new version of a prompt.

  Auto-increments the version number and extracts variables from
  the template.
  """
  @spec create_prompt_version(Prompt.t(), String.t()) ::
          {:ok, PromptVersion.t()} | {:error, Changeset.t()}
  def create_prompt_version(%Prompt{} = prompt, template) do
    variables = extract_variables(template)
    version_number = get_next_version_number(prompt.id)

    %PromptVersion{}
    |> PromptVersion.changeset(%{
      prompt_id: prompt.id,
      version: version_number,
      template: template,
      variables: variables
    })
    |> repo().insert()
  end

  @doc """
  Extracts variable names from a template.

  Variables are identified by {{variable_name}} syntax.
  Returns unique variable names in order of first appearance.
  """
  @spec extract_variables(String.t()) :: [String.t()]
  def extract_variables(template) do
    ~r/\{\{(\w+)\}\}/
    |> Regex.scan(template, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  @doc """
  Returns aggregated evolution metrics for all versions of a prompt.

  Includes pass rates, cost, latency, and per-provider breakdown.
  """
  @spec get_evolution_metrics(binary(), keyword()) :: [map()]
  def get_evolution_metrics(prompt_id, opts \\ []) do
    Evolution.get_metrics(prompt_id, opts)
  end

  # Private functions

  @dialyzer {:nowarn_function, create_prompt_multi: 2, update_prompt_multi: 3}
  defp create_prompt_multi(attrs, template) do
    Multi.new()
    |> Multi.insert(:prompt, Prompt.changeset(%Prompt{}, attrs))
    |> maybe_insert_version(:prompt_version, template)
  end

  defp update_prompt_multi(%Prompt{} = prompt, attrs, template) do
    Multi.new()
    |> Multi.update(:prompt, Prompt.changeset(prompt, attrs))
    |> maybe_insert_version(:prompt_version, template)
  end

  defp maybe_insert_version(multi, _operation_name, template) when template in [nil, ""],
    do: multi

  defp maybe_insert_version(multi, operation_name, template) do
    Multi.run(multi, operation_name, fn repo, %{prompt: prompt} ->
      insert_prompt_version(repo, prompt, template)
    end)
  end

  defp insert_prompt_version(repo, %Prompt{} = prompt, template) do
    variables = extract_variables(template)
    version_number = get_next_version_number(repo, prompt.id)

    %PromptVersion{}
    |> PromptVersion.changeset(%{
      prompt_id: prompt.id,
      version: version_number,
      template: template,
      variables: variables
    })
    |> repo.insert()
  end

  defp ensure_versions_loaded(%Prompt{versions: %Ecto.Association.NotLoaded{}} = prompt) do
    ordered_versions = from(v in PromptVersion, order_by: [desc: v.version])
    repo().preload(prompt, versions: ordered_versions)
  end

  defp ensure_versions_loaded(%Prompt{} = prompt), do: prompt

  defp latest_template(%Prompt{versions: versions}) when is_list(versions) do
    case Enum.max_by(versions, & &1.version, fn -> nil end) do
      nil -> ""
      latest_version -> latest_version.template
    end
  end

  defp latest_template(%Prompt{}), do: ""

  defp normalize_attrs(attrs) when is_map(attrs) do
    attrs =
      case Map.has_key?(attrs, :template) do
        true -> Map.put(attrs, "template", Map.get(attrs, :template))
        false -> attrs
      end

    Map.update(attrs, "template", "", &normalize_template/1)
  end

  defp normalize_attrs(attrs), do: attrs

  defp normalized_template(attrs), do: Map.get(attrs, "template", "") |> normalize_template()

  defp normalize_template(template) when is_binary(template) do
    if String.trim(template) == "", do: "", else: template
  end

  defp normalize_template(_), do: ""

  defp prompt_version_error(prompt, attrs, %Changeset{} = version_changeset) do
    prompt_changeset =
      case prompt do
        %Prompt{} = prompt -> Prompt.changeset(prompt, attrs)
        _ -> Prompt.changeset(%Prompt{}, attrs)
      end

    Enum.reduce(version_changeset.errors, prompt_changeset, fn
      {:template, {message, opts}}, acc ->
        Changeset.add_error(acc, :template, message, opts)

      {_field, {message, opts}}, acc ->
        Changeset.add_error(acc, :template, message, opts)
    end)
  end

  defp get_next_version_number(prompt_id), do: get_next_version_number(repo(), prompt_id)

  defp get_next_version_number(repo, prompt_id) do
    query =
      from(v in PromptVersion,
        where: v.prompt_id == ^prompt_id,
        select: max(v.version)
      )

    case repo.one(query) do
      nil -> 1
      max_version -> max_version + 1
    end
  end

  defp maybe_filter_by_search(query, ""), do: query

  defp maybe_filter_by_search(query, search) do
    search_pattern = "%#{search}%"

    where(
      query,
      [p],
      ilike(p.name, ^search_pattern) or ilike(coalesce(p.description, ""), ^search_pattern)
    )
  end

  defp maybe_filter_by_tags(query, []), do: query

  defp maybe_filter_by_tags(query, tags) do
    where(query, [p], fragment("? && ?", p.tags, ^tags))
  end

  defp maybe_filter_by_project_id(query, nil), do: query

  defp maybe_filter_by_project_id(query, project_id),
    do: where(query, [p], p.project_id == ^project_id)

  defp normalize_search(nil), do: ""
  defp normalize_search(search) when is_binary(search), do: String.trim(search)
  defp normalize_search(_search), do: ""

  defp normalize_tags(tags) when is_list(tags), do: Enum.reject(tags, &(&1 == ""))
  defp normalize_tags(_tags), do: []

  defp normalize_project_id(""), do: nil
  defp normalize_project_id(project_id), do: project_id

  defp repo, do: Aludel.Repo.get()
end
