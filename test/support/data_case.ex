defmodule Aludel.DataCase do
  @moduledoc """
  Database-backed ExUnit case with shared data-layer helpers.

  Tests receive Ecto query and changeset imports, project fixtures, and model
  stubs. Each test owns an SQL sandbox connection and installs the default HTTP
  client stub, isolating persisted data and external model requests.

  PostgreSQL-backed tests can use `use Aludel.DataCase, async: true`. Other
  database adapters may require synchronous execution.
  """

  use ExUnit.CaseTemplate

  alias Aludel.Interfaces.HttpClientMock
  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias Aludel.Test.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Aludel.DataCase
      import Aludel.LlmStubs
      import Aludel.PromptsFixtures
      import Aludel.ProvidersFixtures
      import Aludel.EvalsFixtures
    end
  end

  setup tags do
    Aludel.DataCase.setup_sandbox(tags)
    Aludel.DataCase.setup_mox_stub()
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(Aludel.Test.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  @doc """
  Sets up default Mox stub for HTTP client calls using LlmStubs.
  This provides a fallback response for tests that don't set explicit
  expectations.
  """
  def setup_mox_stub do
    Aludel.LlmStubs.setup_default_stub(HttpClientMock)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
