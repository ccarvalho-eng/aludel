import Config

config :aludel_dash, :basic_auth, :disabled

config :aludel_dash, AludelDash.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "aludel_dash_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10,
  priv: "../priv/repo"

config :aludel_dash, AludelDash.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: false,
  debug_errors: true,
  secret_key_base: "LOCAL_DEV_SECRET_PLEASE_CHANGE_IN_PROD",
  watchers: []

config :aludel, :llm,
  openai_api_key: System.get_env("OPENAI_API_KEY"),
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
  google_api_key: System.get_env("GOOGLE_API_KEY"),
  xai_api_key: System.get_env("XAI_API_KEY"),
  groq_api_key: System.get_env("GROQ_API_KEY"),
  openrouter_api_key: System.get_env("OPENROUTER_API_KEY")

config :aludel, Aludel.Storage,
  adapter: Aludel.Interfaces.Storage.Adapters.Local,
  backends: [
    {Aludel.Interfaces.Storage.Adapters.Local,
     [root: System.get_env("ALUDEL_STORAGE_PATH") || "tmp/aludel_uploads"]}
  ]
