defmodule ChroniclesWeb.API.SeriesJSON do
  def index(%{series: series}), do: %{data: Enum.map(series, &data/1)}

  def show(%{series: series}), do: %{data: data(series)}

  defp data(series) do
    %{
      slug: series.slug,
      title: series.title,
      author: series.author.username,
      stories: Enum.map(series.entries, & &1.story.slug)
    }
  end
end
