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

defmodule AludelDash.StorageConfig do
  @moduledoc false

  alias Aludel.Interfaces.Storage.Adapters.AWS
  alias Aludel.Interfaces.Storage.Adapters.GCS
  alias Aludel.Interfaces.Storage.Adapters.Local

  @aws_credential_variables [
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "AWS_SESSION_TOKEN"
  ]
  @backend_order [Local, AWS, GCS]
  @backend_modules %{
    "local" => Local,
    "aws" => AWS,
    "gcs" => GCS
  }

  @type error_reason ::
          {:invalid, String.t()}
          | {:missing, String.t()}
          | {:unsupported_backend, String.t()}
          | :invalid_aws_credentials
          | :invalid_environment
  @type result :: {:ok, keyword()} | {:error, error_reason()}

  @spec resolve(%{optional(String.t()) => term()}) :: result()
  def resolve(environment) when is_map(environment) do
    with {:ok, backend} <- fetch_present(environment, "ALUDEL_STORAGE_BACKEND"),
         {:ok, adapter} <- resolve_adapter(backend),
         {:ok, backends} <- resolve_backends(adapter, environment) do
      {:ok, [adapter: adapter, backends: backends]}
    end
  end

  def resolve(_environment) do
    {:error, :invalid_environment}
  end

  defp resolve_adapter(backend) do
    case Map.fetch(@backend_modules, backend) do
      {:ok, adapter} -> {:ok, adapter}
      :error -> {:error, {:unsupported_backend, backend}}
    end
  end

  defp resolve_backends(active_adapter, environment) do
    @backend_order
    |> Enum.reduce_while({:ok, []}, fn adapter, {:ok, backends} ->
      case maybe_add_backend(adapter, active_adapter, environment, backends) do
        {:ok, updated_backends} -> {:cont, {:ok, updated_backends}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, backends} -> {:ok, Enum.reverse(backends)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_add_backend(adapter, active_adapter, environment, backends) do
    if adapter == active_adapter or backend_configured?(adapter, environment) do
      with {:ok, config} <- resolve_backend_config(adapter, environment) do
        {:ok, [{adapter, config} | backends]}
      end
    else
      {:ok, backends}
    end
  end

  defp resolve_backend_config(Local, environment) do
    with {:ok, root} <- fetch_present(environment, "ALUDEL_STORAGE_PATH"),
         :ok <- validate_local_root(root) do
      {:ok, [root: root]}
    end
  end

  defp resolve_backend_config(AWS, environment) do
    with {:ok, bucket} <- fetch_present(environment, "AWS_S3_BUCKET"),
         {:ok, region} <- fetch_present(environment, "AWS_REGION"),
         {:ok, credential_config} <- resolve_aws_credentials(environment) do
      {:ok, [bucket: bucket, region: region] ++ credential_config}
    end
  end

  defp resolve_backend_config(GCS, environment) do
    with {:ok, bucket} <- fetch_present(environment, "GCS_BUCKET") do
      config =
        [bucket: bucket, goth: Aludel.Goth]
        |> maybe_put_user_project(environment)

      {:ok, config}
    end
  end

  defp backend_configured?(Local, environment) do
    Map.has_key?(environment, "ALUDEL_STORAGE_PATH")
  end

  defp backend_configured?(AWS, environment) do
    Map.has_key?(environment, "AWS_S3_BUCKET") or Map.has_key?(environment, "AWS_REGION")
  end

  defp backend_configured?(GCS, environment) do
    Map.has_key?(environment, "GCS_BUCKET")
  end

  defp validate_local_root(root) do
    if Path.type(root) == :absolute do
      :ok
    else
      {:error, {:invalid, "ALUDEL_STORAGE_PATH"}}
    end
  end

  defp resolve_aws_credentials(environment) do
    credential_states =
      Enum.map(@aws_credential_variables, &credential_state(environment, &1))

    case credential_states do
      [:missing, :missing, :missing] ->
        {:ok, runtime_identity_config()}

      [:present, :present, :missing] ->
        {:ok, explicit_credential_config()}

      [:present, :present, :present] ->
        {:ok, explicit_credential_config() ++ [security_token: {:system, "AWS_SESSION_TOKEN"}]}

      _invalid_or_partial ->
        {:error, :invalid_aws_credentials}
    end
  end

  defp runtime_identity_config do
    [
      access_key_id: [:pod_identity, :instance_role],
      secret_access_key: [:pod_identity, :instance_role],
      security_token: [:pod_identity, :instance_role]
    ]
  end

  defp explicit_credential_config do
    [
      access_key_id: {:system, "AWS_ACCESS_KEY_ID"},
      secret_access_key: {:system, "AWS_SECRET_ACCESS_KEY"}
    ]
  end

  defp credential_state(environment, variable) do
    case Map.get(environment, variable) do
      nil ->
        :missing

      value when is_binary(value) ->
        if String.trim(value) == "" do
          :invalid
        else
          :present
        end

      _invalid ->
        :invalid
    end
  end

  defp maybe_put_user_project(config, environment) do
    case Map.get(environment, "GCS_USER_PROJECT") do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          config
        else
          config ++ [user_project: value]
        end

      _missing_or_invalid ->
        config
    end
  end

  defp fetch_present(environment, variable) do
    case Map.get(environment, variable) do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          {:error, {:missing, variable}}
        else
          {:ok, value}
        end

      _missing_or_invalid ->
        {:error, {:missing, variable}}
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
