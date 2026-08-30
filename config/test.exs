import Config

# Configure test repo for Aludel
config :aludel,
  repo: Aludel.Test.Repo,
  ecto_repos: [Aludel.Test.Repo],
  run_execution_mode: :sequential

config :aludel, Aludel.Test.Repo,
  pool: Ecto.Adapters.SQL.Sandbox,
  priv: "test/support",
  show_sensitive_data_on_connection_error: true,
  stacktrace: true,
  url: System.get_env("DATABASE_URL") || "postgres://postgres:postgres@localhost:5432/aludel_test"

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :aludel, Aludel.Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "jHQ6deVasGy1rWMbTOBYSJIzswGrAo9e8AAvOVQdshCwwZMdQEk1XafnApBV/koE",
  server: false

# In test we don't send emails (config removed as Swoosh is not a dependency for embedded library)

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# LLM Provider API Keys - use bogus keys to prevent hitting real APIs in tests
config :aludel, :llm,
  openai_api_key: "sk-test-fake-openai-key-for-testing",
  anthropic_api_key: "sk-ant-test-fake-anthropic-key-for-testing",
  google_api_key: "sk-test-fake-google-api-key-for-testing",
  xai_api_key: "xai-test-fake-key-for-testing",
  groq_api_key: "gsk-test-fake-key-for-testing",
  openrouter_api_key: "sk-or-test-fake-key-for-testing"

# Use mocked HTTP client for all tests
config :aludel,
  http_client: Aludel.Interfaces.HttpClientMock

# Use stub document converter adapter for tests
config :aludel, :document_converter, adapter: Aludel.Test.StubDocumentConverterAdapter
