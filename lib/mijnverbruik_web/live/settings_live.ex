defmodule MijnverbruikWeb.SettingsLive do
  use MijnverbruikWeb, :live_view

  import MijnverbruikWeb.Format

  alias Mijnverbruik.{Meter, Settings, Tariffs}
  alias Mijnverbruik.Meter.Trend
  alias Mijnverbruik.Settings.Setting
  alias Mijnverbruik.Tariffs.Tariff

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Meter.subscribe()

    tariffs = Tariffs.list_tariffs()
    setting = Settings.get()
    %{latest: latest} = Trend.snapshot()

    {:ok,
     socket
     |> assign(page_title: "Instellingen")
     |> assign(meter: nil, meter_at: nil, offline?: false)
     |> assign(phases: phase_count(latest))
     |> assign(settings_form: to_form(Settings.change(setting)))
     |> assign(location_form: to_form(Settings.change(setting), as: :location))
     |> assign_tariffs(tariffs)
     |> edit(new_tariff(tariffs))}
  end

  defp phase_count({%{phases: phases}, _at}) when phases != [], do: length(phases)
  defp phase_count(_latest), do: 3

  # A new tariff starts today and copies the latest prices, since a contract
  # change usually alters only some of them.
  defp new_tariff([latest | _]),
    do: %Tariff{latest | id: nil, valid_from: Date.utc_today()}

  defp new_tariff([]), do: %Tariff{valid_from: Date.utc_today()}

  defp edit(socket, %Tariff{} = tariff) do
    assign(socket, tariff: tariff, form: to_form(Tariffs.change_tariff(tariff)))
  end

  defp assign_tariffs(socket, tariffs) do
    today = timezone() |> DateTime.now!() |> DateTime.to_date()
    active = Tariffs.valid_on(tariffs, today)

    socket
    |> assign(active_id: active && active.id)
    |> stream(:tariffs, tariffs, reset: true)
  end

  @impl true
  def handle_info({:telegram, telegram}, socket) do
    # What the meter says about itself does not change; only the time does.
    socket =
      if socket.assigns.meter,
        do: socket,
        else: assign(socket, meter: telegram |> Meter.info() |> meter_labels())

    {:noreply,
     assign(socket,
       meter_at: System.os_time(:second),
       offline?: false,
       phases: socket.assigns.meter.phases
     )}
  end

  def handle_info(:meter_offline, socket), do: {:noreply, assign(socket, offline?: true)}

  @impl true
  def handle_event("validate", %{"tariff" => params}, socket) do
    changeset = Tariffs.change_tariff(socket.assigns.tariff, params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"tariff" => params}, socket) do
    result =
      case socket.assigns.tariff do
        %Tariff{id: nil} -> Tariffs.create_tariff(params)
        tariff -> Tariffs.update_tariff(tariff, params)
      end

    case result do
      {:ok, tariff} ->
        if tariff.contract == :dynamic, do: Mijnverbruik.Prices.Fetcher.refresh()
        {:noreply, socket |> put_flash(:info, "Tarief opgeslagen") |> reload()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("save_settings", %{"setting" => params}, socket) do
    case Settings.update(params) do
      {:ok, setting} ->
        {:noreply,
         socket
         |> put_flash(:info, "Hoofdzekering opgeslagen")
         |> assign(settings_form: to_form(Settings.change(setting)))}

      {:error, changeset} ->
        {:noreply, assign(socket, settings_form: to_form(changeset))}
    end
  end

  # The theme script reads the location from <html>, which only a full page
  # load renders again.
  def handle_event("save_location", %{"location" => params}, socket) do
    case Settings.update(params) do
      {:ok, _setting} ->
        {:noreply,
         socket |> put_flash(:info, "Locatie opgeslagen") |> redirect(to: ~p"/settings")}

      {:error, changeset} ->
        {:noreply, assign(socket, location_form: to_form(changeset, as: :location))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket),
    do: {:noreply, edit(socket, Tariffs.get_tariff!(id))}

  def handle_event("cancel", _params, socket),
    do: {:noreply, edit(socket, new_tariff(Tariffs.list_tariffs()))}

  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, _} = id |> Tariffs.get_tariff!() |> Tariffs.delete_tariff()
    {:noreply, socket |> put_flash(:info, "Tarief verwijderd") |> reload()}
  end

  defp reload(socket) do
    tariffs = Tariffs.list_tariffs()
    socket |> assign_tariffs(tariffs) |> edit(new_tariff(tariffs))
  end

  # Dutch labels for what the meter tells about itself.
  defp meter_labels(%{make: make, version: version, phases: phases, gas: gas}) do
    %{
      make: make || "Onbekend",
      protocol: if(version, do: "DSMR #{div(version, 10)}.#{rem(version, 10)}", else: "DSMR"),
      phases: phases,
      gas:
        case gas do
          nil -> "geen"
          :five_minutes -> "elke 5 min"
          :hourly -> "elk uur"
        end
    }
  end

  defp dynamic?(form, field), do: to_string(form[field].value) == "dynamic"

  defp tariff_summary(%Tariff{contract: :dynamic} = t) do
    "Dynamisch · markt + € #{price(t.electricity_surcharge)} · terug markt + € #{price(t.electricity_return)} per kWh · " <>
      common_summary(t)
  end

  defp tariff_summary(%Tariff{} = t) do
    "Vast · normaal € #{price(t.electricity_normal)} · laag € #{price(t.electricity_low)} · terug € #{price(t.electricity_return)} per kWh · " <>
      common_summary(t)
  end

  defp common_summary(t) do
    gas =
      if t.gas_contract == :dynamic,
        do: "gas markt + € #{price(t.gas)} per m³",
        else: "gas € #{price(t.gas)} per m³"

    gas <> " · vast #{euro(Decimal.to_float(t.fixed_per_month))} per maand"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:settings}>
      <h1 class="text-[28px] font-bold tracking-[-0.025em] sm:text-4xl">Instellingen</h1>

      <.section id="meter-title" title="Meter">
        De slimme meter waar het dashboard zijn gegevens van leest.
      </.section>
      <div
        id="meter"
        class="surface flex flex-col gap-[18px] p-5 sm:p-[22px]"
      >
        <p class="flex items-center gap-2.5 text-base font-bold">
          <%= cond do %>
            <% @meter && !@offline? -> %>
              <span class="size-2.5 rounded-full bg-return animate-pulse-dot" /> Verbonden
              <span class="ml-auto font-mono text-xs font-medium text-muted">
                laatste meting {local_time(@meter_at, "%H:%M:%S")}
              </span>
            <% @offline? -> %>
              <span class="size-2.5 rounded-full bg-warn" /> Niet verbonden
            <% true -> %>
              <span class="size-2.5 rounded-full bg-subtle animate-pulse-dot" /> Wachten op de meter…
          <% end %>
        </p>
        <dl :if={@meter} class="grid grid-cols-2 gap-4 md:grid-cols-4">
          <div
            :for={
              {label, value} <- [
                {"Meter", @meter.make},
                {"Protocol", @meter.protocol},
                {"Aansluiting", "#{@meter.phases}-fase"},
                {"Gasmeter", @meter.gas}
              ]
            }
            class="flex min-w-0 flex-col gap-1"
          >
            <dt class="text-xs text-muted">{label}</dt>
            <dd class="truncate font-mono text-sm">{value}</dd>
          </div>
        </dl>
      </div>

      <.section id="fuse-title" title="Hoofdzekering">
        De waarde per fase, gedrukt op de hoofdzekering in je meterkast (3 × 25 A betekent 25 A). Het dashboard laat dan zien hoe dicht elke fase bij uitschakelen zit.
      </.section>
      <.form
        for={@settings_form}
        id="settings-form"
        phx-submit="save_settings"
        class="surface flex flex-col gap-3.5 p-5 sm:flex-row sm:items-end sm:p-[22px]"
      >
        <div class="flex-1">
          <.input
            field={@settings_form[:main_fuse_a]}
            type="select"
            label="Hoofdzekering per fase"
            prompt="Niet ingesteld"
            options={Enum.map(Setting.fuses(), &{"#{@phases} × #{&1} A", &1})}
          />
        </div>
        <.button
          variant="primary"
          size="lg"
          class="self-start sm:self-auto"
          phx-disable-with="Opslaan…"
        >
          Opslaan
        </.button>
      </.form>

      <.section id="tariffs-title" title="Tarieven">
        Prijzen inclusief belastingen, uit je contract. Elk tarief geldt vanaf de ingangsdatum tot het volgende, zodat eerdere kosten de prijzen houden die je toen betaalde.
      </.section>
      <ul
        id="tariffs"
        phx-update="stream"
        class="surface overflow-hidden"
      >
        <li id="tariffs-empty" class="hidden p-[22px] text-[15px] text-muted only:block">
          Nog geen tarieven. Voeg er hieronder een toe om kosten op het dashboard te zien.
        </li>
        <li
          :for={{id, tariff} <- @streams.tariffs}
          id={id}
          class="flex flex-col gap-3.5 border-ink/10 px-5 py-5 not-last:border-b sm:flex-row sm:items-center sm:justify-between sm:gap-5 sm:px-[22px]"
        >
          <div class="flex min-w-0 flex-col gap-1.5">
            <p class="flex items-center gap-2.5 text-[17px] font-bold">
              Vanaf {short_date(tariff.valid_from)}
              <span
                :if={tariff.id == @active_id}
                class="rounded-full bg-return/15 px-2 py-0.5 text-[11px] font-semibold text-return-ink"
              >
                actief
              </span>
            </p>
            <p class="font-mono text-xs leading-relaxed text-muted text-pretty">
              {tariff_summary(tariff)}
            </p>
          </div>
          <div class="flex shrink-0 gap-2">
            <button
              type="button"
              class="min-h-11 rounded-full border border-ink/18 px-4 text-sm font-semibold transition-colors hover:bg-ink/6"
              phx-click="edit"
              phx-value-id={tariff.id}
              aria-label={"Tarief vanaf #{short_date(tariff.valid_from)} bewerken"}
            >
              Bewerken
            </button>
            <button
              type="button"
              class="min-h-11 rounded-full border border-danger/30 px-4 text-sm font-semibold text-danger transition-colors hover:bg-danger/8"
              phx-click="delete"
              phx-value-id={tariff.id}
              data-confirm="Dit tarief verwijderen? Kosten in zijn periode gebruiken dan het tarief ervoor."
              aria-label={"Tarief vanaf #{short_date(tariff.valid_from)} verwijderen"}
            >
              Verwijderen
            </button>
          </div>
        </li>
      </ul>

      <.form
        for={@form}
        id="tariff-form"
        phx-change="validate"
        phx-submit="save"
        class="surface flex flex-col gap-[18px] px-5 py-6 sm:px-[22px]"
      >
        <h2 class="text-[19px] font-bold">
          {if @tariff.id, do: "Tarief bewerken", else: "Tarief toevoegen"} · {if dynamic?(
                                                                                   @form,
                                                                                   :contract
                                                                                 ),
                                                                                 do:
                                                                                   "dynamisch contract",
                                                                                 else: "vast contract"}
        </h2>
        <div class="grid gap-x-[18px] gap-y-4 sm:grid-cols-2">
          <.input field={@form[:valid_from]} type="date" label="Geldig vanaf" />
          <.segmented
            field={@form[:contract]}
            label="Contract"
            options={[{"Vaste prijzen", "fixed"}, {"Dynamisch", "dynamic"}]}
          />
          <%= if dynamic?(@form, :contract) do %>
            <.input
              field={@form[:electricity_surcharge]}
              type="number"
              step="0.00001"
              label="Stroom, bovenop marktprijs (€/kWh)"
            />
            <.input
              field={@form[:electricity_return]}
              type="number"
              step="0.00001"
              label="Teruglevering, bovenop marktprijs (€/kWh)"
            />
            <p class="text-[13px] text-muted text-pretty sm:col-span-2">
              Kosten gebruiken de uurprijs van EnergyZero plus 21% btw plus deze bedragen. Tel voor stroom de energiebelasting en de opslag van je leverancier op, beide incl. btw. Tot de salderingsregeling in 2027 stopt, levert teruggeleverde stroom meestal hetzelfde op: gebruik dan hetzelfde bedrag.
            </p>
          <% else %>
            <.input
              field={@form[:electricity_normal]}
              type="number"
              step="0.00001"
              label="Stroom, normaaltarief (€/kWh)"
            />
            <.input
              field={@form[:electricity_low]}
              type="number"
              step="0.00001"
              label="Stroom, daltarief (€/kWh)"
            />
            <.input
              field={@form[:electricity_return]}
              type="number"
              step="0.00001"
              label="Terugleververgoeding (€/kWh)"
            />
            <div class="hidden sm:block" />
          <% end %>
          <.input
            field={@form[:gas_contract]}
            type="select"
            label="Gascontract"
            options={[{"Vaste prijs", "fixed"}, {"Dynamisch (dagprijs)", "dynamic"}]}
          />
          <.input
            field={@form[:gas]}
            type="number"
            step="0.00001"
            label={
              if dynamic?(@form, :gas_contract),
                do: "Gas, bovenop marktprijs (€/m³)",
                else: "Gas (€/m³)"
            }
          />
          <p
            :if={dynamic?(@form, :gas_contract)}
            class="text-[13px] text-muted text-pretty sm:col-span-2"
          >
            Gaskosten gebruiken de marktprijs van EnergyZero per gasdag (06:00 tot 06:00) plus 21% btw plus dit bedrag: energiebelasting en de opslag van je leverancier, beide incl. btw.
          </p>
          <div class="sm:col-span-2">
            <.input
              field={@form[:fixed_per_month]}
              type="number"
              step="0.01"
              label="Vaste kosten (€/maand)"
              hint="Vastrecht en netbeheerkosten voor stroom en gas, min de vermindering energiebelasting (heffingskorting)."
            />
          </div>
        </div>
        <div class="flex gap-2">
          <.button variant="primary" size="lg" phx-disable-with="Opslaan…">Tarief opslaan</.button>
          <.button :if={@tariff.id} type="button" size="lg" phx-click="cancel">Annuleren</.button>
        </div>
      </.form>

      <.section id="display-title" title="Weergave" />
      <div class="surface flex flex-col gap-3.5 px-5 pb-[22px] pt-3.5 sm:px-[22px]">
        <div id="display-controls" phx-update="ignore" class="flex flex-col gap-3.5">
          <div class="flex min-h-12 items-center justify-between gap-4 border-b border-ink/10 pb-3.5">
            <div class="flex min-w-0 flex-col gap-[3px]">
              <span id="sky-label" class="text-base font-semibold">Lucht volgt de tijd van de dag</span>
              <span class="text-[13px] text-muted text-pretty">
                Ochtend, middag, avond en nacht kleuren de achtergrond.
              </span>
            </div>
            <button
              type="button"
              role="switch"
              aria-checked="true"
              aria-labelledby="sky-label"
              data-sky-switch
              phx-click={JS.dispatch("phx:set-sky")}
              class="group relative h-8 w-[52px] shrink-0 rounded-full bg-ink/20 transition-colors duration-200 aria-checked:bg-return"
            >
              <span class="absolute left-[3px] top-[3px] size-[26px] rounded-full bg-white shadow-[0_2px_6px_rgba(10,20,40,.25)] transition-transform duration-200 group-aria-checked:translate-x-5" />
            </button>
          </div>
          <div class="flex flex-col gap-2">
            <span id="theme-label" class="text-[13px] font-semibold text-muted">Thema</span>
            <div
              role="radiogroup"
              aria-labelledby="theme-label"
              class="flex gap-0.5 rounded-full bg-ink/10 p-1 text-sm font-semibold"
            >
              <button
                :for={
                  {label, value} <- [{"Automatisch", "auto"}, {"Licht", "day"}, {"Donker", "night"}]
                }
                type="button"
                role="radio"
                aria-checked={to_string(value == "auto")}
                data-phx-theme={value}
                phx-click={JS.dispatch("phx:set-theme")}
                class="flex-1 rounded-full py-3 text-center text-muted transition-colors duration-200 hover:text-ink aria-checked:bg-inverse aria-checked:text-on-inverse"
              >
                {label}
              </button>
            </div>
          </div>
        </div>
        <.form
          for={@location_form}
          id="location-form"
          phx-submit="save_location"
          class="flex flex-col gap-3.5 border-t border-ink/10 pt-3.5"
        >
          <div class="flex flex-col gap-[3px]">
            <span class="text-base font-semibold">Locatie</span>
            <span class="text-[13px] text-muted text-pretty">
              Automatisch wisselt bij zonsopkomst en zonsondergang op deze plek. Leeg is De Bilt.
            </span>
          </div>
          <div class="grid gap-x-[18px] gap-y-4 sm:grid-cols-[1fr_1fr_auto] sm:items-end">
            <.input
              field={@location_form[:latitude]}
              type="number"
              step="any"
              label="Breedtegraad"
              placeholder="52.1"
            />
            <.input
              field={@location_form[:longitude]}
              type="number"
              step="any"
              label="Lengtegraad"
              placeholder="5.18"
            />
            <.button
              variant="primary"
              size="lg"
              class="self-start sm:self-auto"
              phx-disable-with="Opslaan…"
            >
              Opslaan
            </.button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  slot :inner_block

  defp section(assigns) do
    ~H"""
    <header class="mt-4 flex flex-col gap-1.5">
      <h2 id={@id} class="text-[22px] font-bold tracking-[-0.015em]">{@title}</h2>
      <p :if={@inner_block != []} class="max-w-[720px] text-[15px] text-muted text-pretty">
        {render_slot(@inner_block)}
      </p>
    </header>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :options, :list, required: true, doc: "`{label, value}` tuples"

  # Radio buttons drawn as a segmented control.
  defp segmented(assigns) do
    ~H"""
    <fieldset class="flex min-w-0 flex-col gap-2">
      <legend class="mb-2 text-[13px] font-semibold text-muted">{@label}</legend>
      <div class="flex gap-0.5 rounded-full bg-ink/10 p-1 text-sm font-semibold">
        <label
          :for={{label, value} <- @options}
          class="flex-1 cursor-pointer rounded-full py-3 text-center text-muted transition-colors duration-200 hover:text-ink has-checked:bg-inverse has-checked:text-on-inverse has-focus-visible:ring-4 has-focus-visible:ring-inverse/20"
        >
          <input
            type="radio"
            id={"#{@field.id}_#{value}"}
            name={@field.name}
            value={value}
            checked={to_string(@field.value) == value}
            class="sr-only"
          />
          {label}
        </label>
      </div>
    </fieldset>
    """
  end
end
