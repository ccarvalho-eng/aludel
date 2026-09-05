defmodule AludelDash.Repo do
  use Ecto.Repo, otp_app: :aludel_dash, adapter: Ecto.Adapters.Postgres
end

defmodule AludelDash.ErrorHTML do
  use Phoenix.Component

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end

defmodule AludelDash.BasicAuth do
  @moduledoc false

  @realm "Aludel Dashboard"

  @spec init(keyword()) :: keyword()
  def init(opts) do
    opts
  end

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case Application.fetch_env!(:aludel_dash, :basic_auth) do
      :disabled ->
        conn

      credentials when is_list(credentials) ->
        Plug.BasicAuth.basic_auth(conn, credentials)

      _invalid ->
        raise ArgumentError, "invalid standalone Basic Authentication configuration"
    end
  end

  @spec validate_credentials(String.t() | nil, String.t() | nil) ::
          {:ok, keyword()} | {:error, :invalid_credentials}
  def validate_credentials(username, password)
      when is_binary(username) and is_binary(password) do
    if valid_username?(username) and present?(password) do
      {:ok, username: username, password: password, realm: @realm}
    else
      {:error, :invalid_credentials}
    end
  end

  def validate_credentials(_username, _password) do
    {:error, :invalid_credentials}
  end

  defp valid_username?(username) do
    present?(username) and not String.contains?(username, ":")
  end

  defp present?(value) do
    String.trim(value) != ""
  end
end

defmodule AludelDash.DatabaseConfig do
  @moduledoc false

  @component_variables [
    "DATABASE_HOST",
    "DATABASE_USERNAME",
    "DATABASE_PASSWORD",
    "DATABASE_NAME"
  ]

  @type result :: {:ok, keyword(String.t())} | {:error, :invalid_database_config}

  @spec resolve(%{optional(String.t()) => term()}) :: result()
  def resolve(environment) when is_map(environment) do
    if component_configuration?(environment) do
      resolve_components(environment)
    else
      resolve_url(environment)
    end
  end

  def resolve(_environment) do
    {:error, :invalid_database_config}
  end

  defp component_configuration?(environment) do
    Enum.any?(@component_variables, &Map.has_key?(environment, &1))
  end

  defp resolve_components(environment) do
    with {:ok, hostname} <- fetch_present(environment, "DATABASE_HOST"),
         {:ok, username} <- fetch_present(environment, "DATABASE_USERNAME"),
         {:ok, password} <- fetch_present(environment, "DATABASE_PASSWORD"),
         {:ok, database} <- fetch_present(environment, "DATABASE_NAME") do
      {:ok, hostname: hostname, username: username, password: password, database: database}
    end
  end

  defp resolve_url(environment) do
    with {:ok, url} <- fetch_present(environment, "DATABASE_URL") do
      {:ok, url: url}
    end
  end

  defp fetch_present(environment, variable) do
    case Map.get(environment, variable) do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          {:error, :invalid_database_config}
        else
          {:ok, value}
        end

      _missing_or_invalid ->
        {:error, :invalid_database_config}
    end
  end
end

defmodule AludelDash.Resolver do
  @behaviour Aludel.Web.Resolver

  @impl true
  def resolve_user(_conn), do: nil

  @impl true
  def resolve_access(_user) do
    if Application.get_env(:aludel_dash, :read_only, false) do
      :read_only
    else
      :all
    end
  end

  @impl true
  def resolve_refresh(_user), do: 5
end

defmodule AludelDash.Router do
  use Phoenix.Router, helpers: false

  import Aludel.Web.Router

  pipeline :browser do
    plug(:fetch_session)
    plug(AludelDash.BasicAuth)
  end

  scope "/" do
    pipe_through(:browser)

    aludel_dashboard("/", resolver: AludelDash.Resolver)
  end
end

defmodule AludelDash.Endpoint do
  use Phoenix.Endpoint, otp_app: :aludel_dash

  socket("/live", Phoenix.LiveView.Socket)

  plug(Plug.Session,
    store: :cookie,
    key: "_aludel_dash_key",
    signing_salt: "aludel_dashboard"
  )

  plug(AludelDash.Router)
end

defmodule AludelDash.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AludelDash.Repo,
      {Phoenix.PubSub, name: AludelDash.PubSub},
      AludelDash.Endpoint
    ]

    opts = [strategy: :one_for_one, name: AludelDash.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
