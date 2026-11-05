defmodule Chronicles.StoriesFixtures do
  @moduledoc "Stories for tests, from the story files in test/fixtures/stories."

  alias Chronicles.Stories

  def story_fixture(scope, slug \\ "the-number", visibility \\ :private) do
    {:ok, story} = Stories.create_story(scope.user, slug, Chronicles.Play.story(slug), visibility)
    Stories.get_story!(scope, story.slug)
  end
end
