defmodule Aludel.Web.AssetsTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Aludel.Web.Assets

  describe "call/2 :css" do
    test "returns 404 when asset not found" do
      conn =
        conn(:get, "/assets/css-abc123.css")
        |> Map.put(:params, %{"md5" => "abc123"})
        |> Assets.call(:css)

      assert conn.status == 404
      assert conn.resp_body == "Not Found"
    end
  end

  describe "call/2 :js" do
    test "returns 404 when asset not found" do
      conn =
        conn(:get, "/assets/js-abc123.js")
        |> Map.put(:params, %{"md5" => "abc123"})
        |> Assets.call(:js)

      assert conn.status == 404
      assert conn.resp_body == "Not Found"
    end

    test "tag input renders persisted tags as text" do
      source = File.read!("assets/js/hooks/tag_input.js")
      bundle = File.read!("priv/static/app.js")

      assert source =~ "document.createTextNode(tag)"
      assert source =~ "removeBtn.textContent = '×'"
      refute source =~ "chip.innerHTML"

      assert bundle =~ "document.createTextNode(tag)"
      refute bundle =~ "chip.innerHTML"
    end
  end

  describe "call/2 :font" do
    test "returns 404 when font not found" do
      conn =
        conn(:get, "/assets/fonts/Inter.woff2")
        |> Map.put(:params, %{"path" => "Inter.woff2"})
        |> Assets.call(:font)

      assert conn.status == 404
      assert conn.resp_body == "Not Found"
    end
  end

  describe "call/2 :icon" do
    test "returns 404 when icon not found" do
      conn =
        conn(:get, "/assets/icons/outline/check.svg")
        |> Map.put(:params, %{"path" => "outline/check.svg"})
        |> Assets.call(:icon)

      assert conn.status == 404
      assert conn.resp_body == "Not Found"
    end
  end
end
