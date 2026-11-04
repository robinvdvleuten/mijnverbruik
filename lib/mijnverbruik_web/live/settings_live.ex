defmodule MijnverbruikWeb.SettingsLive do
  use MijnverbruikWeb, :live_view

  import MijnverbruikWeb.Format

  alias Mijnverbruik.{Settings, Tariffs}
  alias Mijnverbruik.Settings.Setting
  alias Mijnverbruik.Tariffs.Tariff

  @impl true
  def mount(_params, _session, socket) do
    tariffs = Tariffs.list_tariffs()

    {:ok,
     socket
     |> assign(page_title: "Settings")
     |> assign(settings_form: to_form(Settings.change(Settings.get())))
     |> stream(:tariffs, tariffs)
     |> edit(new_tariff(tariffs))}
  end

  # A new tariff starts today and copies the latest prices, since a contract
  # change usually alters only some of them.
  defp new_tariff([latest | _]),
    do: %Tariff{latest | id: nil, valid_from: Date.utc_today()}

  defp new_tariff([]), do: %Tariff{valid_from: Date.utc_today()}

  defp edit(socket, %Tariff{} = tariff) do
    assign(socket, tariff: tariff, form: to_form(Tariffs.change_tariff(tariff)))
  end

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
        {:noreply, socket |> put_flash(:info, "Tariff saved") |> reload()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("save_settings", %{"setting" => params}, socket) do
    case Settings.update(params) do
      {:ok, setting} ->
        {:noreply,
         socket
         |> put_flash(:info, "Settings saved")
         |> assign(settings_form: to_form(Settings.change(setting)))}

      {:error, changeset} ->
        {:noreply, assign(socket, settings_form: to_form(changeset))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket),
    do: {:noreply, edit(socket, Tariffs.get_tariff!(id))}

  def handle_event("cancel", _params, socket),
    do: {:noreply, edit(socket, new_tariff(Tariffs.list_tariffs()))}

  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, _} = id |> Tariffs.get_tariff!() |> Tariffs.delete_tariff()
    {:noreply, socket |> put_flash(:info, "Tariff deleted") |> reload()}
  end

  defp reload(socket) do
    tariffs = Tariffs.list_tariffs()

    socket
    |> stream(:tariffs, tariffs, reset: true)
    |> edit(new_tariff(tariffs))
  end

  defp dynamic?(form, field), do: to_string(form[field].value) == "dynamic"

  defp tariff_summary(%Tariff{contract: :dynamic} = t) do
    "Dynamic · market + €#{price(t.electricity_surcharge)} per kWh · return market + €#{price(t.electricity_return)} · " <>
      common_summary(t)
  end

  defp tariff_summary(%Tariff{} = t) do
    "Normal €#{price(t.electricity_normal)} · Low €#{price(t.electricity_low)} · Return €#{price(t.electricity_return)} per kWh · " <>
      common_summary(t)
  end

  defp common_summary(t) do
    gas =
      if t.gas_contract == :dynamic,
        do: "Gas market + €#{price(t.gas)} per m³",
        else: "Gas €#{price(t.gas)} per m³"

    gas <> " · Fixed #{euro(Decimal.to_float(t.fixed_per_month))} per month"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:settings}>
      <h1 class="text-2xl font-semibold">Settings</h1>

      <section aria-labelledby="connection-title" class="mt-8 space-y-4">
        <div>
          <h2 id="connection-title" class="text-sm font-medium">Main fuse</h2>
          <p class="mt-1 text-sm text-base-content/60">
            The rating per phase, printed on the main fuse in your meter cupboard (e.g. 3×25 A means 25 A). The dashboard then shows how close each phase is to tripping it.
          </p>
        </div>
        <.form
          for={@settings_form}
          id="settings-form"
          phx-submit="save_settings"
          class="flex items-end gap-3 rounded-xl border border-base-300 p-4"
        >
          <div class="grow">
            <.input
              field={@settings_form[:main_fuse_a]}
              type="select"
              label="Main fuse per phase"
              prompt="Not set"
              options={Enum.map(Setting.fuses(), &{"#{&1} A", &1})}
            />
          </div>
          <.button variant="primary" class="btn btn-primary mb-2" phx-disable-with="Saving…">
            Save
          </.button>
        </.form>
      </section>

      <section aria-labelledby="tariffs-title" class="mt-8 space-y-4">
        <div>
          <h2 id="tariffs-title" class="text-sm font-medium">Tariffs</h2>
          <p class="mt-1 text-sm text-base-content/60">
            Prices including taxes, from your contract. Each tariff applies from its date until the next one, so past costs keep the prices you paid then.
          </p>
        </div>

        <ul
          id="tariffs"
          phx-update="stream"
          class="divide-y divide-base-300 rounded-xl border border-base-300"
        >
          <li id="tariffs-empty" class="hidden p-4 text-sm text-base-content/60 only:block">
            No tariffs yet. Add one below to see costs on the dashboard.
          </li>
          <li
            :for={{id, tariff} <- @streams.tariffs}
            id={id}
            class="flex items-start justify-between gap-4 p-4"
          >
            <div class="min-w-0 space-y-1">
              <p class="text-sm font-medium">
                From {Calendar.strftime(tariff.valid_from, "%-d %b %Y")}
              </p>
              <p class="text-xs tabular-nums text-base-content/60">
                {tariff_summary(tariff)}
              </p>
            </div>
            <div class="flex shrink-0 gap-1">
              <button
                type="button"
                class="btn btn-ghost btn-sm"
                phx-click="edit"
                phx-value-id={tariff.id}
                aria-label={"Edit tariff from #{tariff.valid_from}"}
              >
                <.icon name="hero-pencil-square" class="size-4" />
              </button>
              <button
                type="button"
                class="btn btn-ghost btn-sm text-error"
                phx-click="delete"
                phx-value-id={tariff.id}
                data-confirm="Delete this tariff? Costs for its period will use the tariff before it."
                aria-label={"Delete tariff from #{tariff.valid_from}"}
              >
                <.icon name="hero-trash" class="size-4" />
              </button>
            </div>
          </li>
        </ul>

        <.form
          for={@form}
          id="tariff-form"
          phx-change="validate"
          phx-submit="save"
          class="rounded-xl border border-base-300 p-4"
        >
          <h3 class="mb-3 text-sm font-medium">
            {if @tariff.id, do: "Edit tariff", else: "Add tariff"}
          </h3>
          <.input field={@form[:valid_from]} type="date" label="Valid from" />
          <.input
            field={@form[:contract]}
            type="select"
            label="Contract"
            options={[{"Fixed prices", "fixed"}, {"Dynamic (hourly market prices)", "dynamic"}]}
          />
          <div class="grid gap-x-4 sm:grid-cols-2">
            <%= if dynamic?(@form, :contract) do %>
              <.input
                field={@form[:electricity_surcharge]}
                type="number"
                step="0.00001"
                label="Electricity, on top of market price (€/kWh)"
              />
              <.input
                field={@form[:electricity_return]}
                type="number"
                step="0.00001"
                label="Return, on top of market price (€/kWh)"
              />
              <p class="-mt-1 mb-3 text-xs text-base-content/60 sm:col-span-2">
                Costs use EnergyZero's hourly market price plus 21% VAT plus these amounts. For usage, add energy tax and your supplier's markup, both including VAT. Until net metering ends in 2027, returned kWh usually earn the same: use the same amount for return.
              </p>
            <% else %>
              <.input
                field={@form[:electricity_normal]}
                type="number"
                step="0.00001"
                label="Electricity, normal tariff (€/kWh)"
              />
              <.input
                field={@form[:electricity_low]}
                type="number"
                step="0.00001"
                label="Electricity, low tariff (€/kWh)"
              />
              <.input
                field={@form[:electricity_return]}
                type="number"
                step="0.00001"
                label="Return compensation (€/kWh)"
              />
            <% end %>
          </div>
          <div class="grid gap-x-4 sm:grid-cols-2">
            <.input
              field={@form[:gas_contract]}
              type="select"
              label="Gas contract"
              options={[{"Fixed price", "fixed"}, {"Dynamic (daily market price)", "dynamic"}]}
            />
            <.input
              field={@form[:gas]}
              type="number"
              step="0.00001"
              label={
                if dynamic?(@form, :gas_contract),
                  do: "Gas, on top of market price (€/m³)",
                  else: "Gas (€/m³)"
              }
            />
            <p
              :if={dynamic?(@form, :gas_contract)}
              class="-mt-1 mb-3 text-xs text-base-content/60 sm:col-span-2"
            >
              Gas costs use EnergyZero's market price for each gas day (06:00 to 06:00) plus 21% VAT plus this amount: energy tax and your supplier's markup, both including VAT.
            </p>
          </div>
          <.input
            field={@form[:fixed_per_month]}
            type="number"
            step="0.01"
            label="Fixed costs (€/month)"
          />
          <p class="-mt-1 mb-3 text-xs text-base-content/60">
            Standing charges and grid fees for electricity and gas, minus the energy tax credit (heffingskorting).
          </p>
          <div class="flex gap-2">
            <.button variant="primary" phx-disable-with="Saving…">Save tariff</.button>
            <.button :if={@tariff.id} type="button" phx-click="cancel">Cancel</.button>
          </div>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
