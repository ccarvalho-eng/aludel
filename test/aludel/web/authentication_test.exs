defmodule Aludel.Web.AuthenticationTest do
  use ExUnit.Case, async: true

  alias Aludel.Web.Authentication

  describe "on_mount/4" do
    test "assigns access and refresh from session" do
      session = %{
        "access" => :read_only,
        "refresh" => 10,
        "user" => %{id: 1}
      }

      socket = %Phoenix.LiveView.Socket{
        private: %{connect_params: %{}, connect_info: %{session: session}}
      }

      {:cont, updated_socket} = Authentication.on_mount(:default, %{}, session, socket)

      assert updated_socket.assigns.access == :read_only
      assert updated_socket.assigns.refresh == 10
      assert updated_socket.assigns.user == %{id: 1}
    end

    test "assigns all session values to socket" do
      session = %{
        "access" => :all,
        "refresh" => 5,
        "user" => %{id: 2, name: "Admin"},
        "resolver" => MyApp.Resolver,
        "aludel_name" => :aludel,
        "prefix" => "/admin",
        "logo_path" => "/logo.png",
        "csp_nonces" => %{img: "abc", style: "def", script: "ghi"}
      }

      socket = %Phoenix.LiveView.Socket{
        private: %{connect_params: %{}, connect_info: %{session: session}}
      }

      {:cont, updated_socket} = Authentication.on_mount(:default, %{}, session, socket)

      assert updated_socket.assigns.access == :all
      assert updated_socket.assigns.refresh == 5
      assert updated_socket.assigns.user == %{id: 2, name: "Admin"}
      assert updated_socket.assigns.resolver == MyApp.Resolver
      assert updated_socket.assigns.aludel_name == :aludel
      assert updated_socket.assigns.prefix == "/admin"
      assert updated_socket.assigns.logo_path == "/logo.png"
      assert updated_socket.assigns.csp_nonces == %{img: "abc", style: "def", script: "ghi"}
    end
  end

  describe "authorize_event/3" do
    test "blocks mutations for read-only access" do
      provider_socket = socket(Aludel.Web.ProviderLive.Index, :read_only)
      run_socket = socket(Aludel.Web.RunLive.New, :read_only)

      assert {:halt, updated_socket} =
               Authentication.authorize_event("delete", %{}, provider_socket)

      assert updated_socket.assigns.flash["error"] =~ "read-only"
      assert {:halt, _socket} = Authentication.authorize_event("save", %{}, run_socket)
    end

    test "allows inspection events for read-only access" do
      socket = socket(Aludel.Web.PromptLive.Index, :read_only)

      assert {:cont, ^socket} = Authentication.authorize_event("search", %{}, socket)
    end

    test "classifies events by view as well as name" do
      new_suite_socket = socket(Aludel.Web.SuiteLive.New, :read_only)
      existing_suite_socket = socket(Aludel.Web.SuiteLive.Show, :read_only)

      assert {:cont, ^new_suite_socket} =
               Authentication.authorize_event("add_test_case", %{}, new_suite_socket)

      assert {:halt, _socket} =
               Authentication.authorize_event("add_test_case", %{}, existing_suite_socket)
    end

    test "allows all events for full access" do
      socket = socket(Aludel.Web.ProviderLive.Index, :all)

      assert {:cont, ^socket} = Authentication.authorize_event("delete", %{}, socket)
      assert {:cont, ^socket} = Authentication.authorize_event("future_event", %{}, socket)
    end

    test "denies unknown events and invalid access values" do
      read_only_socket = socket(Aludel.Web.DashboardLive, :read_only)
      invalid_socket = socket(Aludel.Web.DashboardLive, :unexpected)

      assert {:halt, _socket} =
               Authentication.authorize_event("future_event", %{}, read_only_socket)

      assert {:halt, _socket} =
               Authentication.authorize_event("toggle_cost_view", %{}, invalid_socket)
    end
  end

  defp socket(view, access) do
    %Phoenix.LiveView.Socket{
      view: view,
      assigns: %{__changed__: %{}, access: access, flash: %{}},
      private: %{live_temp: %{}}
    }
  end
end
