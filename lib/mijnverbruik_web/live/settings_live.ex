defmodule MijnverbruikWeb.SettingsLive do
  use MijnverbruikWeb, :live_view

  import MijnverbruikWeb.Format

  alias Mijnverbruik.Tariffs
  alias Mijnverbruik.Tariffs.Tariff

  @impl true
  def mount(_params, _session, socket) do
    tariffs = Tariffs.list_tariffs()

    {:ok,
     socket
     |> assign(page_title: "Settings")
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
      {:ok, _tariff} ->
        {:noreply, socket |> put_flash(:info, "Tariff saved") |> reload()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:settings}>
      <h1 class="text-2xl font-semibold">Settings</h1>

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
                Normal €{price(tariff.electricity_normal)} · Low €{price(tariff.electricity_low)} · Return €{price(
                  tariff.electricity_return
                )} per kWh · Gas €{price(tariff.gas)} per m³ · Fixed {euro(
                  Decimal.to_float(tariff.fixed_per_month)
                )} per month
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
          <div class="grid gap-x-4 sm:grid-cols-2">
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
            <.input field={@form[:gas]} type="number" step="0.00001" label="Gas (€/m³)" />
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
