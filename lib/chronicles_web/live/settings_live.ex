defmodule ChroniclesWeb.SettingsLive do
  @moduledoc """
  General settings: language and theme. Works for visitors too, so it is not tied to
  an account. Account details live in `ChroniclesWeb.UserLive.Account`.
  """
  use ChroniclesWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <h1 class="text-2xl font-semibold tracking-tight">{gettext("Settings")}</h1>

      <section id="language-setting" class="flex items-center justify-between gap-4">
        <h2 class="font-medium">{gettext("Language")}</h2>
        <div class="flex gap-1 rounded-field bg-base-200 p-1 text-sm">
          <.link
            :for={{code, name} <- [{"en", "English"}, {"nl", "Nederlands"}]}
            id={"locale-#{code}"}
            href={~p"/locale?#{[locale: code]}"}
            method="put"
            lang={code}
            aria-current={code == @locale && "true"}
            class="rounded-field px-3 py-1 opacity-70 transition hover:opacity-100 aria-[current]:bg-base-100 aria-[current]:font-semibold aria-[current]:opacity-100 aria-[current]:shadow-sm"
          >
            {name}
          </.link>
        </div>
      </section>

      <section id="theme-setting" class="flex items-center justify-between gap-4">
        <h2 class="font-medium">{gettext("Theme")}</h2>
        <Layouts.theme_toggle />
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("Settings"),
       locale: Gettext.get_locale(ChroniclesWeb.Gettext)
     )}
  end
end
