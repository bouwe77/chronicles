defmodule ChroniclesWeb.API.SagaJSON do
  def index(%{saga: saga}), do: %{data: Enum.map(saga, &data/1)}

  def show(%{saga: saga}), do: %{data: data(saga)}

  defp data(saga) do
    %{
      slug: saga.slug,
      title: saga.title,
      author: saga.author.username,
      stories: Enum.map(saga.chapters, & &1.story.slug)
    }
  end
end
