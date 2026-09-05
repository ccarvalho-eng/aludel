import Config

config :aludel_dash, :basic_auth, :disabled

config :aludel_dash, AludelDash.Endpoint, server: false

config :aludel, Aludel.Storage,
  adapter: Aludel.Interfaces.Storage.Adapters.Local,
  backends: [{Aludel.Interfaces.Storage.Adapters.Local, [root: "tmp/aludel_test_uploads"]}]
