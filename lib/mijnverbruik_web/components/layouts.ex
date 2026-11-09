defmodule MijnverbruikWeb.Layouts do
  @moduledoc """
  The root page and the app shell: a sky backdrop, a floating navigation bar
  with the time and meter status, and a centred content column.
  """
  use MijnverbruikWeb, :html

  embed_templates "layouts/*"

  # On <html>, for the theme script that switches to night at sunset.
  defp location_attrs do
    %{latitude: lat, longitude: lon} = Mijnverbruik.Settings.location()
    %{"data-latitude" => lat, "data-longitude" => lon}
  end

  @doc """
  Renders the app shell.

  ## Examples

      <Layouts.app flash={@flash} active={:dashboard}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :active, :atom, default: nil, doc: "the nav item of the current page"

  attr :meter, :atom,
    values: [nil, :live, :offline],
    default: nil,
    doc: "the meter's state, shown next to the clock when known"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="relative min-h-screen overflow-x-clip">
      <div class="sky" aria-hidden="true">
        <div
          class="cloud"
          style="left: 2%; top: 120px; width: 36%; opacity: .7; animation-duration: 70s"
        />
        <div class="cloud" style="left: 60%; top: 80px; width: 42%; opacity: .6" />
        <div
          class="cloud"
          style="left: 30%; top: 520px; width: 50%; opacity: .4; animation-duration: 110s"
        />
        <div class="stars" />
      </div>

      <header class="absolute inset-x-0 top-[18px] z-10 flex justify-center px-4">
        <nav
          aria-label="Hoofdmenu"
          class="flex items-center gap-1.5 whitespace-nowrap rounded-full border border-bar-line bg-bar py-[5px] pl-2.5 pr-[5px] shadow-float backdrop-blur-xl sm:gap-3.5 sm:pl-4"
        >
          <.link navigate={~p"/"} class="flex items-center gap-2" aria-label="mijnverbruik">
            <span class="grid size-6 place-items-center rounded-lg bg-inverse">
              <span class="size-2 rounded-full bg-use"></span>
            </span>
            <span class="hidden text-base font-bold tracking-[-0.02em] sm:inline">mijnverbruik</span>
          </.link>
          <div class="flex gap-0.5 text-sm font-semibold">
            <.nav_link :for={{key, label, path} <- nav_items()} path={path} active={@active == key}>
              {label}
            </.nav_link>
          </div>
          <.clock meter={@meter} />
        </nav>
      </header>

      <main class="relative mx-auto flex w-full max-w-[992px] flex-col gap-3.5 px-4 pb-8 pt-[92px] sm:gap-4 sm:pb-14 sm:pt-[104px]">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  defp nav_items do
    [
      {:dashboard, "Nu", ~p"/"},
      {:history, "Geschiedenis", ~p"/history"},
      {:settings, "Instellingen", ~p"/settings"}
    ]
  end

  attr :path, :string, required: true
  attr :active, :boolean, required: true
  slot :inner_block, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@path}
      aria-current={@active && "page"}
      class={[
        "rounded-full px-3 py-3 transition-colors duration-200 sm:px-4 sm:py-[9px]",
        if(@active,
          do: "bg-inverse text-on-inverse",
          else: "text-muted hover:bg-inverse/8 hover:text-ink"
        )
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :meter, :atom, required: true

  # The local time, kept current in the browser, with a pulsing dot while the
  # meter sends data. Hidden on phones, where the menu needs the room.
  defp clock(assigns) do
    assigns =
      assign(assigns, time: MijnverbruikWeb.Format.local_time(System.os_time(:second), "%H:%M"))

    ~H"""
    <div class="hidden items-center gap-2 pr-3 font-mono text-xs text-muted sm:flex">
      <span
        :if={@meter}
        id="meter-dot"
        class={[
          "size-2 rounded-full",
          if(@meter == :live, do: "animate-pulse-dot bg-return", else: "bg-warn")
        ]}
      />
      <%= if @meter == :offline do %>
        offline
      <% else %>
        <time id="clock" phx-hook=".Clock" phx-update="ignore">{@time}</time>
      <% end %>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Clock">
        export default {
          mounted() {
            const tick = () => {
              this.el.textContent = new Date().toLocaleTimeString("nl-NL", {hour: "2-digit", minute: "2-digit"})
            }
            tick()
            this.timer = setInterval(tick, 1000)
          },
          destroyed() { clearInterval(this.timer) }
        }
      </script>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="Geen verbinding"
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Opnieuw verbinden
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Er ging iets mis"
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Opnieuw verbinden
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
