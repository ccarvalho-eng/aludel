defmodule AludelDash.BasicAuthTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias AludelDash.BasicAuth

  setup do
    original_config = Application.get_env(:aludel_dash, :basic_auth)

    on_exit(fn ->
      restore_config(original_config)
    end)
  end

  test "valid credentials continue through the plug" do
    configure_credentials("admin", "correct horse battery staple")

    conn =
      :get
      |> conn("/")
      |> put_req_header(
        "authorization",
        Plug.BasicAuth.encode_basic_auth("admin", "correct horse battery staple")
      )
      |> BasicAuth.call([])

    refute conn.halted
  end

  test "passwords containing a colon remain valid" do
    configure_credentials("admin", "correct:horse")

    conn =
      :get
      |> conn("/")
      |> put_req_header(
        "authorization",
        Plug.BasicAuth.encode_basic_auth("admin", "correct:horse")
      )
      |> BasicAuth.call([])

    refute conn.halted
  end

  test "missing and incorrect request credentials receive the challenge" do
    configure_credentials("admin", "correct horse battery staple")

    for authorization <- [
          nil,
          "Basic invalid",
          Plug.BasicAuth.encode_basic_auth("admin", "wrong")
        ] do
      conn = conn(:get, "/")

      conn =
        case authorization do
          nil -> conn
          value -> put_req_header(conn, "authorization", value)
        end

      conn = BasicAuth.call(conn, [])

      assert conn.halted
      assert conn.status == 401
      assert conn.resp_body == "Unauthorized"
      assert get_resp_header(conn, "www-authenticate") == [~s(Basic realm="Aludel Dashboard")]
    end
  end

  test "missing and malformed application configuration fail closed" do
    Application.delete_env(:aludel_dash, :basic_auth)

    assert_raise ArgumentError, fn ->
      BasicAuth.call(conn(:get, "/"), [])
    end

    Application.put_env(:aludel_dash, :basic_auth, nil)

    assert_raise ArgumentError, fn ->
      BasicAuth.call(conn(:get, "/"), [])
    end
  end

  test "explicitly disabled development authentication allows requests" do
    Application.put_env(:aludel_dash, :basic_auth, :disabled)

    refute BasicAuth.call(conn(:get, "/"), []).halted
  end

  test "credential validation rejects unsafe production values" do
    invalid_values = [
      {nil, nil},
      {"admin", nil},
      {nil, "password"},
      {"", "password"},
      {"admin", ""},
      {"   ", "password"},
      {"admin", "   "},
      {"admin:operator", "password"}
    ]

    for {username, password} <- invalid_values do
      assert {:error, :invalid_credentials} =
               BasicAuth.validate_credentials(username, password)
    end
  end

  defp configure_credentials(username, password) do
    assert {:ok, credentials} = BasicAuth.validate_credentials(username, password)
    Application.put_env(:aludel_dash, :basic_auth, credentials)
  end

  defp restore_config(nil) do
    Application.delete_env(:aludel_dash, :basic_auth)
  end

  defp restore_config(config) do
    Application.put_env(:aludel_dash, :basic_auth, config)
  end
end
