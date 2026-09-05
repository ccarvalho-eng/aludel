import Config

if System.get_env("PHX_SERVER") do
  config :aludel_dash, AludelDash.Endpoint, server: true
end

if config_env() == :prod do
  basic_auth =
    case AludelDash.BasicAuth.validate_credentials(
           System.get_env("BASIC_AUTH_USER"),
           System.get_env("BASIC_AUTH_PASS")
         ) do
      {:ok, credentials} ->
        credentials

      {:error, :invalid_credentials} ->
        raise """
        BASIC_AUTH_USER and BASIC_AUTH_PASS must both be set to nonblank values.
        BASIC_AUTH_USER cannot contain a colon.
        """
    end

  database_config =
    case AludelDash.DatabaseConfig.resolve(System.get_env()) do
      {:ok, config} ->
        config

      {:error, :invalid_database_config} ->
        raise """
        Configure DATABASE_URL or all of DATABASE_HOST, DATABASE_USERNAME,
        DATABASE_PASSWORD, and DATABASE_NAME with nonblank values.
        """
    end

  repo_config =
    Keyword.put(
      database_config,
      :pool_size,
      String.to_integer(System.get_env("POOL_SIZE") || "10")
    )

  config :aludel_dash, AludelDash.Repo, repo_config

  storage_config =
    case AludelDash.StorageConfig.resolve(System.get_env()) do
      {:ok, config} ->
        config

      {:error, {:missing, variable}} ->
        raise "#{variable} must be set to a nonblank value."

      {:error, {:invalid, variable}} ->
        raise "#{variable} is invalid. Use an absolute path for local storage."

      {:error, {:unsupported_backend, _backend}} ->
        raise "ALUDEL_STORAGE_BACKEND must be one of: local, aws, gcs."

      {:error, :invalid_aws_credentials} ->
        raise """
        AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must both be nonblank when either is set.
        AWS_SESSION_TOKEN is optional and requires the explicit key pair.
        Omit all three variables to use the AWS runtime identity provider.
        """

      {:error, :invalid_environment} ->
        raise "Unable to read standalone storage configuration."
    end

  config :aludel, Aludel.Storage, storage_config

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      """

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :aludel_dash, AludelDash.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base

  config :aludel_dash,
    basic_auth: basic_auth,
    read_only: System.get_env("READ_ONLY") == "true"

  config :aludel, :llm,
    openai_api_key: System.get_env("OPENAI_API_KEY"),
    anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
    google_api_key: System.get_env("GOOGLE_API_KEY"),
    xai_api_key: System.get_env("XAI_API_KEY"),
    groq_api_key: System.get_env("GROQ_API_KEY"),
    openrouter_api_key: System.get_env("OPENROUTER_API_KEY")
end
