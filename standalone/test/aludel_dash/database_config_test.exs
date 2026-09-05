defmodule AludelDash.DatabaseConfigTest do
  use ExUnit.Case, async: true

  alias AludelDash.DatabaseConfig

  test "resolves the existing database URL configuration" do
    assert {:ok, [url: "postgres://user:password@localhost/database"]} =
             DatabaseConfig.resolve(%{
               "DATABASE_URL" => "postgres://user:password@localhost/database"
             })
  end

  test "resolves complete component configuration" do
    assert {:ok, config} =
             DatabaseConfig.resolve(%{
               "DATABASE_HOST" => "db",
               "DATABASE_USERNAME" => "aludel",
               "DATABASE_PASSWORD" => "strong-password",
               "DATABASE_NAME" => "aludel_dash"
             })

    assert config == [
             hostname: "db",
             username: "aludel",
             password: "strong-password",
             database: "aludel_dash"
           ]
  end

  test "component configuration takes precedence and preserves reserved characters" do
    password = ":/@%?#[]!$&'()*+,;="

    assert {:ok, config} =
             DatabaseConfig.resolve(%{
               "DATABASE_URL" => "postgres://old:default@localhost/old",
               "DATABASE_HOST" => "db",
               "DATABASE_USERNAME" => "aludel",
               "DATABASE_PASSWORD" => password,
               "DATABASE_NAME" => "aludel_dash"
             })

    assert config[:password] == password
    refute Keyword.has_key?(config, :url)
  end

  test "partial or blank component configuration fails closed" do
    complete = %{
      "DATABASE_HOST" => "db",
      "DATABASE_USERNAME" => "aludel",
      "DATABASE_PASSWORD" => "strong-password",
      "DATABASE_NAME" => "aludel_dash"
    }

    for variable <- Map.keys(complete) do
      assert {:error, :invalid_database_config} =
               complete
               |> Map.delete(variable)
               |> DatabaseConfig.resolve()

      assert {:error, :invalid_database_config} =
               complete
               |> Map.put(variable, "   ")
               |> DatabaseConfig.resolve()
    end
  end

  test "missing or blank URL configuration fails closed" do
    assert {:error, :invalid_database_config} = DatabaseConfig.resolve(%{})

    assert {:error, :invalid_database_config} =
             DatabaseConfig.resolve(%{"DATABASE_URL" => "   "})
  end
end
