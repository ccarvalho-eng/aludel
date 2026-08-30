defmodule Aludel.DatasetsFixtures do
  @moduledoc """
  Test fixtures for reusable datasets and their entries.
  """

  def dataset_fixture(attrs \\ %{}) do
    {:ok, dataset} =
      attrs
      |> Enum.into(%{
        name: "Support conversations",
        description: "Representative support requests",
        metadata: %{"team" => "support"}
      })
      |> Aludel.Datasets.create_dataset()

    dataset
  end

  def dataset_entry_fixture(attrs \\ %{}) do
    dataset = Map.get_lazy(attrs, :dataset, &dataset_fixture/0)

    entry_attrs =
      attrs
      |> Map.delete(:dataset)
      |> Enum.into(%{
        name: "Password reset",
        variable_values: %{},
        messages: [
          %{"role" => "system", "content" => "Be concise."},
          %{"role" => "assistant", "content" => "How can I help?"},
          %{"role" => "user", "content" => "Reset my password."}
        ],
        assertions: [%{"type" => "contains", "value" => "reset"}],
        metadata: %{"locale" => "en"}
      })

    {:ok, entry} = Aludel.Datasets.create_entry(dataset, entry_attrs)
    entry
  end
end
