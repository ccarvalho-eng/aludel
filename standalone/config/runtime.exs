import Config

if System.get_env("PHX_SERVER") do
  config :aludel_dash, AludelDash.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      """

  config :aludel_dash, AludelDash.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

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
    basic_auth_user: System.get_env("BASIC_AUTH_USER"),
    basic_auth_pass: System.get_env("BASIC_AUTH_PASS"),
    read_only: System.get_env("READ_ONLY") == "true"

  config :aludel, :llm,
    openai_api_key: System.get_env("OPENAI_API_KEY"),
    anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
    google_api_key: System.get_env("GOOGLE_API_KEY"),
    xai_api_key: System.get_env("XAI_API_KEY"),
    groq_api_key: System.get_env("GROQ_API_KEY"),
    openrouter_api_key: System.get_env("OPENROUTER_API_KEY")
end
