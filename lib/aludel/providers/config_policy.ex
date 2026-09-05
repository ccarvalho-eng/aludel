defmodule Aludel.Providers.ConfigPolicy do
  @moduledoc false

  @error_message "must not contain credentials; configure them at runtime"

  @credential_fragments ~w(
    apikey
    apisecret
    authorization
    credential
    passwd
    password
    privatekey
    secret
  )

  @credential_suffixes ~w(
    accesskey
    accesskeyid
    accountkey
    cookie
    encryptionkey
    sessionkey
    signingkey
    subscriptionkey
    token
  )

  @credential_keys ~w(auth bearer key)

  @spec error_message() :: String.t()
  def error_message do
    @error_message
  end

  @spec validate(term()) :: :ok | {:error, :credentials_not_allowed}
  def validate(config) do
    if contains_credentials?(config) do
      {:error, :credentials_not_allowed}
    else
      :ok
    end
  end

  @spec sanitize(term()) :: term()
  def sanitize(config) when is_map(config) do
    Enum.reduce(config, %{}, fn {key, value}, sanitized ->
      if credential_key?(key) do
        sanitized
      else
        Map.put(sanitized, key, sanitize(value))
      end
    end)
  end

  def sanitize(config) when is_list(config) do
    config
    |> Enum.reduce([], fn
      {key, value}, sanitized when is_binary(key) or is_atom(key) ->
        if credential_key?(key) do
          sanitized
        else
          [{key, sanitize(value)} | sanitized]
        end

      value, sanitized ->
        [sanitize(value) | sanitized]
    end)
    |> Enum.reverse()
  end

  def sanitize(config) do
    config
  end

  defp contains_credentials?(config) when is_map(config) do
    Enum.any?(config, fn {key, value} ->
      credential_key?(key) or contains_credentials?(value)
    end)
  end

  defp contains_credentials?(config) when is_list(config) do
    Enum.any?(config, fn
      {key, value} when is_binary(key) or is_atom(key) ->
        credential_key?(key) or contains_credentials?(value)

      value ->
        contains_credentials?(value)
    end)
  end

  defp contains_credentials?(_config) do
    false
  end

  defp credential_key?(key) when is_binary(key) or is_atom(key) do
    key
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]/u, "")
    |> credential_key_name?()
  end

  defp credential_key?(_key) do
    false
  end

  defp credential_key_name?(key) do
    key in @credential_keys or
      Enum.any?(@credential_fragments, &String.contains?(key, &1)) or
      Enum.any?(@credential_suffixes, &String.ends_with?(key, &1))
  end
end
