defmodule Aludel.DockerComposeTest do
  use ExUnit.Case, async: true

  @compose_file Path.expand("../../docker-compose.yaml", __DIR__)

  setup_all do
    compose = @compose_file |> File.read!() |> YamlElixir.read_from_string!()
    {:ok, compose: compose}
  end

  test "database is private and requires an operator-supplied password", %{compose: compose} do
    database = get_in(compose, ["services", "db"])

    refute Map.has_key?(database, "ports")

    assert database["environment"] == %{
             "POSTGRES_USER" => "${POSTGRES_USER:-postgres}",
             "POSTGRES_PASSWORD" => "${POSTGRES_PASSWORD:?Set POSTGRES_PASSWORD in .env}",
             "POSTGRES_DB" => "${POSTGRES_DB:-aludel_dash}"
           }
  end

  test "web receives matching database components", %{compose: compose} do
    web_environment = get_in(compose, ["services", "web", "environment"])

    assert web_environment == %{
             "DATABASE_HOST" => "db",
             "DATABASE_USERNAME" => "${POSTGRES_USER:-postgres}",
             "DATABASE_PASSWORD" => "${POSTGRES_PASSWORD:?Set POSTGRES_PASSWORD in .env}",
             "DATABASE_NAME" => "${POSTGRES_DB:-aludel_dash}"
           }
  end

  test "healthcheck expands database identity inside the container", %{compose: compose} do
    assert get_in(compose, ["services", "db", "healthcheck", "test"]) == [
             "CMD-SHELL",
             ~s(pg_isready -U "$${POSTGRES_USER}" -d "$${POSTGRES_DB}")
           ]
  end
end
