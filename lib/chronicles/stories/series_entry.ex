defmodule Chronicles.Stories.SeriesEntry do
  @moduledoc "One story's place in a series, counted from 1."
  use Ecto.Schema

  @primary_key false
  schema "series_stories" do
    belongs_to :series, Chronicles.Stories.Series
    belongs_to :story, Chronicles.Stories.Story
    field :position, :integer
  end
end
