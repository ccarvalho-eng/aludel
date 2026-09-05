# Define Error HTML for tests
defmodule Aludel.Web.ErrorHTML do
  use Phoenix.Component

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end

# Define Error JSON for tests
defmodule Aludel.Web.ErrorJSON do
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end

# Configure endpoint for testing
Application.put_env(:aludel, Aludel.Web.Endpoint,
  check_origin: false,
  http: [port: 4002],
  live_view: [signing_salt: "test_signing_salt"],
  pubsub_server: Aludel.PubSub,
  render_errors: [formats: [html: Aludel.Web.ErrorHTML], layout: false],
  secret_key_base: String.duplicate("a", 64),
  server: false,
  url: [host: "localhost"]
)

# Define test router
defmodule Aludel.Web.Test.ReadOnlyResolver do
  @behaviour Aludel.Web.Resolver

  @impl true
  def resolve_user(_conn) do
    %{id: "read-only-user"}
  end

  @impl true
  def resolve_access(_user) do
    :read_only
  end

  @impl true
  def resolve_refresh(_user) do
    5
  end
end

defmodule Aludel.Web.Test.Router do
  use Phoenix.Router

  import Aludel.Web.Router

  pipeline :browser do
    plug :fetch_session
    plug :fetch_flash
  end

  scope "/" do
    pipe_through :browser
    aludel_dashboard("/")
  end

  scope "/read-only" do
    pipe_through :browser

    aludel_dashboard("/",
      as: :read_only_aludel,
      resolver: Aludel.Web.Test.ReadOnlyResolver
    )
  end
end

# Define test endpoint
defmodule Aludel.Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :aludel

  socket "/live", Phoenix.LiveView.Socket

  plug Plug.Session,
    store: :cookie,
    key: "_aludel_test_key",
    signing_salt: "test_salt"

  plug Aludel.Web.Test.Router
end

# Start test repo
Aludel.Test.Repo.start_link()

# Start endpoint
Aludel.Web.Endpoint.start_link()

# Set sandbox mode for test repo
Ecto.Adapters.SQL.Sandbox.mode(Aludel.Test.Repo, :manual)

# Define Mox mock for HTTP client
Mox.defmock(Aludel.Interfaces.HttpClientMock,
  for: Aludel.Interfaces.Adapters.Http
)

Mox.defmock(Aludel.Interfaces.Storage.Adapters.AWS.ClientMock,
  for: Aludel.Interfaces.Storage.Adapters.AWS.Client
)

Mox.defmock(Aludel.Interfaces.Storage.Adapters.GCS.ClientMock,
  for: Aludel.Interfaces.Storage.Adapters.GCS.Client
)

Mox.defmock(Aludel.Interfaces.StorageMock,
  for: Aludel.Interfaces.Storage.Behaviour
)

Mox.defmock(Aludel.ExecutorMock, for: Aludel.Executor)

ExUnit.start()
