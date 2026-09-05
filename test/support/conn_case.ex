defmodule Aludel.Web.ConnCase do
  @moduledoc """
  Connection-backed ExUnit case for controller and LiveView behavior.

  Tests receive `Plug.Conn`, `Phoenix.ConnTest`, and `Phoenix.LiveViewTest`
  helpers with the default Aludel endpoint. Each test also uses the isolated SQL
  sandbox setup from `Aludel.DataCase` and receives a fresh connection.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint Aludel.Web.Endpoint

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import Aludel.Web.ConnCase
    end
  end

  setup tags do
    Aludel.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
