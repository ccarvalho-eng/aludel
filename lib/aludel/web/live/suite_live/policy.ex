defmodule Aludel.Web.SuiteLive.Policy do
  @moduledoc """
  LiveView for creating and inspecting immutable suite quality policies.
  """

  use Aludel.Web, :live_view

  alias Aludel.Evals
  alias Aludel.Evals.QualityPolicy

  @max_definition_bytes 100_000
  @starter_definition %{
    "schema_version" => 1,
    "rules" => [
      %{"id" => "overall", "type" => "overall_pass_rate", "minimum" => 0.9}
    ]
  }

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_params(%{"id" => id}, _uri, socket) do
    suite = Evals.get_suite!(id)
    policies = Evals.list_suite_policies(suite)
    definition = policies |> List.first() |> initial_definition()

    {:noreply,
     socket
     |> assign(:page_title, "#{suite.name} quality policy")
     |> assign(:suite, suite)
     |> assign(:policies, policies)
     |> assign_definition(definition)}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"policy" => params}, socket) do
    {:noreply, assign_definition(socket, Map.get(params, "definition", ""))}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"policy" => params}, socket) do
    definition_json = Map.get(params, "definition", "")

    case parse_definition(definition_json) do
      {:ok, definition} ->
        create_policy(socket, definition, definition_json)

      {:error, errors} ->
        {:noreply, assign_invalid_definition(socket, definition_json, errors)}
    end
  end

  defp create_policy(socket, definition, definition_json) do
    case Evals.create_suite_policy(socket.assigns.suite, definition) do
      {:ok, policy} ->
        policies = Evals.list_suite_policies(socket.assigns.suite)

        {:noreply,
         socket
         |> assign(:policies, policies)
         |> assign_definition(format_definition(policy.definition))
         |> put_flash(:info, "Policy version #{policy.version} created")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign_invalid_definition(definition_json, ["Policy version could not be created"])
         |> put_flash(:error, "Policy version could not be created")}
    end
  end

  defp assign_definition(socket, definition_json) do
    case parse_definition(definition_json) do
      {:ok, definition} ->
        socket
        |> assign(:policy_form, policy_form(definition_json))
        |> assign(:validation_errors, [])
        |> assign(:rule_count, rule_count(definition))

      {:error, errors} ->
        assign_invalid_definition(socket, definition_json, errors)
    end
  end

  defp assign_invalid_definition(socket, definition_json, errors) do
    socket
    |> assign(:policy_form, policy_form(definition_json))
    |> assign(:validation_errors, errors)
    |> assign(:rule_count, 0)
  end

  defp parse_definition(definition_json)
       when is_binary(definition_json) and byte_size(definition_json) <= @max_definition_bytes do
    with {:ok, definition} <- Jason.decode(definition_json),
         :ok <- QualityPolicy.validate(definition) do
      {:ok, definition}
    else
      {:error, %Jason.DecodeError{}} -> {:error, ["Definition must be valid JSON"]}
      {:error, errors} when is_list(errors) -> {:error, errors}
    end
  end

  defp parse_definition(definition_json) when is_binary(definition_json) do
    {:error, ["Definition cannot exceed #{@max_definition_bytes} bytes"]}
  end

  defp parse_definition(_definition_json) do
    {:error, ["Definition must be valid JSON"]}
  end

  defp initial_definition(nil) do
    format_definition(@starter_definition)
  end

  defp initial_definition(policy) do
    format_definition(policy.definition)
  end

  defp policy_form(definition) do
    to_form(%{"definition" => definition}, as: :policy)
  end

  defp rule_count(%{"rules" => rules}) when is_list(rules) do
    length(rules)
  end

  defp rule_count(_definition) do
    0
  end

  defp rule_count_label(1) do
    "1 rule"
  end

  defp rule_count_label(count) do
    "#{count} rules"
  end

  defp format_definition(definition) do
    Jason.encode!(definition, pretty: true)
  end
end
