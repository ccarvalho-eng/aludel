defmodule Aludel.Evals.MessageValidator do
  @moduledoc false

  @roles ~w(assistant system user)

  @spec validate(term()) :: :ok | {:error, String.t()}
  def validate(messages) when is_list(messages) do
    case validate_messages(messages) do
      :ok -> validate_final_turn(messages)
      error -> error
    end
  end

  def validate(_messages) do
    {:error, "must be a list of messages"}
  end

  defp validate_messages(messages) do
    Enum.reduce_while(messages, :ok, fn message, :ok ->
      case validate_message(message) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_message(%{"role" => role, "content" => content} = message) do
    cond do
      role not in @roles ->
        {:error, "contains an unsupported role"}

      not is_binary(content) or String.trim(content) == "" ->
        {:error, "contains blank content"}

      invalid_metadata?(Map.get(message, "metadata")) ->
        {:error, "contains invalid metadata"}

      true ->
        :ok
    end
  end

  defp validate_message(_message) do
    {:error, "must contain role and content"}
  end

  defp validate_final_turn([]) do
    :ok
  end

  defp validate_final_turn(messages) do
    case List.last(messages) do
      %{"role" => "user"} -> :ok
      _message -> {:error, "must end with a user turn"}
    end
  end

  defp invalid_metadata?(nil) do
    false
  end

  defp invalid_metadata?(metadata) when not is_map(metadata) do
    true
  end

  defp invalid_metadata?(metadata) do
    match?({:error, _reason}, Jason.encode(metadata))
  end
end
