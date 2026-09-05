defmodule Aludel.Web.Router do
  @moduledoc """
  Provides the aludel_dashboard macro for mounting Aludel in host apps.
  """

  alias Aludel.Web.Resolver

  @default_opts [
    resolver: Aludel.Web.Resolver,
    socket_path: "/live",
    transport: "websocket"
  ]

  @transport_values ~w(longpoll websocket)

  @doc """
  Defines an Aludel dashboard route.

  ## Options

  * `:as` - override route name (default: :aludel_dashboard)
  * `:csp_nonce_assign_key` - CSP nonce keys (nil, atom, or map)
  * `:logo_path` - custom logo link path
  * `:on_mount` - additional mount hooks
  * `:aludel_name` - Aludel instance name (default: Aludel)
  * `:resolver` - Aludel.Web.Resolver implementation
  * `:socket_path` - phoenix socket path (default: "/live")
  * `:transport` - "websocket" or "longpoll" (default: "websocket")

  ## Examples

      scope "/" do
        pipe_through :browser
        aludel_dashboard "/aludel"
      end
  """
  defmacro aludel_dashboard(path, opts \\ []) do
    opts =
      if Macro.quoted_literal?(opts) do
        Macro.prewalk(opts, &expand_alias(&1, __CALLER__))
      else
        opts
      end

    quote bind_quoted: binding() do
      prefix = Phoenix.Router.scoped_path(__MODULE__, path)

      scope path, alias: false, as: false do
        import Phoenix.LiveView.Router, only: [live: 4, live_session: 3]

        {session_name, session_opts, route_opts} =
          Aludel.Web.Router.__options__(prefix, opts)

        live_session session_name, session_opts do
          get "/css-:md5", Aludel.Web.Assets, :css, as: :aludel_web_asset
          get "/js-:md5", Aludel.Web.Assets, :js, as: :aludel_web_asset
          get "/fonts/*path", Aludel.Web.Assets, :font, as: :aludel_web_font
          get "/icons/*path", Aludel.Web.Assets, :icon, as: :aludel_web_icon
          get "/images/*path", Aludel.Web.Assets, :image, as: :aludel_web_image

          live "/", Aludel.Web.DashboardLive, :index, route_opts

          live "/prompts", Aludel.Web.PromptLive.Index, :index, route_opts
          live "/prompts/new", Aludel.Web.PromptLive.New, :new, route_opts
          live "/prompts/:id/edit", Aludel.Web.PromptLive.New, :edit, route_opts
          live "/prompts/:id/evolution", Aludel.Web.PromptLive.Evolution, :show, route_opts
          get "/prompts/:id/evolution/export/:format", Aludel.Web.ExportController, :evolution
          live "/prompts/:id", Aludel.Web.PromptLive.Show, :show, route_opts

          live "/runs/new", Aludel.Web.RunLive.New, :new, route_opts
          get "/runs/results/:id/export", Aludel.Web.ExportController, :run_result
          live "/runs/:id", Aludel.Web.RunLive.Show, :show, route_opts

          live "/suites", Aludel.Web.SuiteLive.Index, :index, route_opts
          live "/suites/new", Aludel.Web.SuiteLive.New, :new, route_opts
          get "/suites/runs/:id/export", Aludel.Web.ExportController, :suite_run
          get "/suites/runs/:id/report/:format", Aludel.Web.ExportController, :suite_report
          live "/suites/runs/:id/report", Aludel.Web.SuiteLive.Report, :show, route_opts
          live "/suites/:id/policy", Aludel.Web.SuiteLive.Policy, :show, route_opts
          live "/suites/:id", Aludel.Web.SuiteLive.Show, :show, route_opts

          live "/datasets", Aludel.Web.DatasetLive.Index, :index, route_opts

          live "/datasets/:id/red-team/catalog",
               Aludel.Web.DatasetLive.RedTeamCatalog,
               :show,
               route_opts

          live "/datasets/:id", Aludel.Web.DatasetLive.Show, :show, route_opts

          live "/providers", Aludel.Web.ProviderLive.Index, :index, route_opts
          live "/providers/new", Aludel.Web.ProviderLive.New, :new, route_opts
          live "/providers/:id/edit", Aludel.Web.ProviderLive.New, :edit, route_opts
        end
      end
    end
  end

  @doc false
  def __options__(prefix, opts) do
    opts = Keyword.merge(@default_opts, opts)

    Enum.each(opts, &validate_opt!/1)

    on_mount = List.wrap(Keyword.get(opts, :on_mount, [])) ++ [Aludel.Web.Authentication]

    session_args = [
      prefix,
      opts[:aludel_name],
      opts[:resolver],
      opts[:socket_path],
      opts[:transport],
      opts[:csp_nonce_assign_key],
      opts[:logo_path]
    ]

    session_opts = [
      on_mount: on_mount,
      session: {__MODULE__, :__session__, session_args},
      root_layout: {Aludel.Web.Layouts, :root}
    ]

    session_name = Keyword.get(opts, :as, :aludel_dashboard)

    {session_name, session_opts, as: session_name}
  end

  @doc false
  def __session__(
        conn,
        prefix,
        aludel_name,
        resolver,
        live_path,
        live_transport,
        csp_key,
        logo_path
      ) do
    user = Resolver.call_with_fallback(resolver, :resolve_user, [conn])
    csp_keys = expand_csp_nonce_keys(csp_key)

    %{
      "prefix" => prefix,
      "aludel_name" => aludel_name,
      "user" => user,
      "resolver" => resolver,
      "access" => Resolver.call_with_fallback(resolver, :resolve_access, [user]),
      "refresh" => Resolver.call_with_fallback(resolver, :resolve_refresh, [user]),
      "live_path" => live_path,
      "live_transport" => live_transport,
      "logo_path" => logo_path,
      "csp_nonces" => %{
        img: conn.assigns[csp_keys[:img]],
        style: conn.assigns[csp_keys[:style]],
        script: conn.assigns[csp_keys[:script]]
      }
    }
  end

  # Private functions

  defp expand_alias({:__aliases__, _, _} = alias_ast, env) do
    Macro.expand(alias_ast, %{env | function: {:aludel_dashboard, 2}})
  end

  defp expand_alias(other, _env), do: other

  defp expand_csp_nonce_keys(nil), do: %{img: nil, style: nil, script: nil}
  defp expand_csp_nonce_keys(key) when is_atom(key), do: %{img: key, style: key, script: key}
  defp expand_csp_nonce_keys(map) when is_map(map), do: map

  defp validate_opt!({:transport, transport}) do
    unless transport in @transport_values do
      raise ArgumentError, """
      invalid :transport, expected one of #{inspect(@transport_values)},
      got #{inspect(transport)}
      """
    end
  end

  defp validate_opt!({:socket_path, path}) do
    unless is_binary(path) and byte_size(path) > 0 do
      raise ArgumentError, """
      invalid :socket_path, expected a binary URL, got: #{inspect(path)}
      """
    end
  end

  defp validate_opt!({:resolver, resolver}) do
    unless is_atom(resolver) and not is_nil(resolver) do
      raise ArgumentError, """
      invalid :resolver, expected a module implementing Aludel.Web.Resolver,
      got: #{inspect(resolver)}
      """
    end
  end

  defp validate_opt!({:aludel_name, name}) do
    unless is_atom(name) do
      raise ArgumentError, """
      invalid :aludel_name, expected a module or atom,
      got #{inspect(name)}
      """
    end
  end

  defp validate_opt!({:logo_path, path}) do
    unless is_nil(path) or (is_binary(path) and byte_size(path) > 0) do
      raise ArgumentError, """
      invalid :logo_path, expected nil or a non-empty binary path,
      got: #{inspect(path)}
      """
    end
  end

  defp validate_opt!({:csp_nonce_assign_key, key}) do
    unless is_nil(key) or is_atom(key) or is_map(key) do
      raise ArgumentError, """
      invalid :csp_nonce_assign_key, expected nil, atom, or map with
      atom keys, got #{inspect(key)}
      """
    end
  end

  defp validate_opt!(_option), do: :ok
end
