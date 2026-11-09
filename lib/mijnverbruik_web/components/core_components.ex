defmodule MijnverbruikWeb.CoreComponents do
  @moduledoc """
  Core UI building blocks: flash notices, buttons, form inputs and icons,
  styled with the design tokens in `assets/css/app.css`.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welkom terug!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="fixed right-4 top-20 z-50 w-[calc(100%-2rem)] max-w-sm cursor-pointer sm:top-24"
      {@rest}
    >
      <div class="flex items-start gap-3 rounded-[20px] border border-tile-line bg-tile p-4 text-sm shadow-float backdrop-blur-xl">
        <span class={[
          "mt-1.5 size-2.5 shrink-0 rounded-full",
          if(@kind == :error, do: "bg-danger", else: "bg-return")
        ]} />
        <div class="min-w-0 flex-1">
          <p :if={@title} class="font-bold">{@title}</p>
          <p class="text-muted">{msg}</p>
        </div>
        <button type="button" class="group shrink-0" aria-label="Sluiten">
          <.icon name="hero-x-mark" class="size-5 text-subtle group-hover:text-ink" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  A frosted card, the surface most content sits on.

  ## Examples

      <.card id="gas">
        <:title>Gas</:title>
        <:aside>per uur</:aside>
        …
      </.card>
  """
  attr :id, :string, default: nil
  attr :class, :any, default: nil
  attr :stale, :boolean, default: false, doc: "dims the card while its values are not current"
  attr :rest, :global
  slot :title, doc: "a heading at the top left"
  slot :aside, doc: "a short note at the top right, in mono"
  slot :inner_block

  def card(assigns) do
    ~H"""
    <section
      id={@id}
      class={[
        "flex min-w-0 flex-col gap-2.5 rounded-3xl border border-tile-line bg-tile px-5 py-[18px] backdrop-blur-xl sm:px-[22px] sm:py-5",
        @class
      ]}
      {@rest}
    >
      <header :if={@title != [] or @aside != []} class="flex items-baseline justify-between gap-2.5">
        <h2 class="text-[17px] font-bold tracking-[-0.01em]">{render_slot(@title)}</h2>
        <span :if={@aside != []} class="whitespace-nowrap font-mono text-[11px] text-subtle">
          {render_slot(@aside)}
        </span>
      </header>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc """
  A big number with a small unit after it.

  ## Examples

      <.figure value="2,14" unit="kWh" />
  """
  attr :id, :string, default: nil
  attr :value, :string, required: true
  attr :unit, :string, default: nil
  attr :size, :string, default: "text-[30px]", doc: "the number's text size class"
  attr :class, :any, default: nil

  def figure(assigns) do
    ~H"""
    <p class={["flex items-baseline gap-1.5", @class]}>
      <span id={@id} class={["font-bold leading-none tracking-[-0.035em]", @size]}>{@value}</span>
      <span :if={@unit} class="text-xs font-semibold text-muted">{@unit}</span>
    </p>
    """
  end

  @doc """
  A small coloured dot that ties a value to its colour in charts.
  """
  attr :class, :any, required: true

  def dot(assigns) do
    ~H"""
    <span class={["size-2 shrink-0 rounded-full", @class]} aria-hidden="true" />
    """
  end

  @doc """
  A warning across the page, for something that needs attention.

  ## Examples

      <.banner id="offline" title="Meter niet bereikbaar">Laatste meting om 08:09.</.banner>
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :tone, :atom, values: [:warn, :danger], default: :warn
  slot :inner_block, required: true
  slot :action

  def banner(assigns) do
    ~H"""
    <div
      id={@id}
      role="alert"
      class={[
        "flex flex-wrap items-center gap-x-3.5 gap-y-1 rounded-[18px] border px-5 py-3.5",
        if(@tone == :danger,
          do: "border-danger/50 bg-danger/12 text-ink",
          else: "border-warn-line bg-warn-bg text-on-warn"
        )
      ]}
    >
      <p class="flex items-center gap-2.5 text-[15px] font-bold">
        <span class={[
          "size-2.5 shrink-0 rounded-full",
          if(@tone == :danger, do: "bg-danger", else: "bg-warn")
        ]} />
        {@title}
      </p>
      <p class="min-w-0 flex-1 basis-60 text-sm text-pretty">{render_slot(@inner_block)}</p>
      {render_slot(@action)}
    </div>
    """
  end

  @doc """
  Renders a pill button, or a link styled as one.

  ## Examples

      <.button>Annuleren</.button>
      <.button phx-click="go" variant="primary">Opslaan</.button>
      <.button navigate={~p"/"}>Terug</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled type)
  attr :class, :any, default: nil
  attr :variant, :string, values: [nil, "primary"], default: nil
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    assigns =
      assign(assigns,
        class: [
          "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-full px-5 py-2.5 text-sm font-bold transition duration-200 active:scale-[.97] disabled:opacity-50 phx-submit-loading:opacity-70",
          if(assigns.variant == "primary",
            do: "bg-inverse text-on-inverse shadow-float hover:-translate-y-px",
            else: "bg-track text-ink hover:bg-inverse/15"
          ),
          assigns.class
        ]
      )

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  <.input field={@form[:kind]} type="select" options={["Vast": "fixed"]} />
  ```
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :hint, :string, default: nil, doc: "a short explanation under the field"
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step inputmode)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="min-w-0">
      <label for={@id} class="flex items-center gap-2 text-sm">
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={@class || "size-4 rounded accent-(--ink)"}
          {@rest}
        />{@label}
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="min-w-0">
      <label for={@id} class="block">
        <span :if={@label} class="mb-2 block text-[13px] font-semibold text-muted">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[
            @class || field_class(@errors),
            "appearance-none bg-(image:--chevron) bg-position-[right_1rem_center] bg-no-repeat pr-10"
          ]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <p :if={@hint} class="mt-2 text-[13px] text-muted text-pretty">{@hint}</p>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="min-w-0">
      <label for={@id} class="block">
        <span :if={@label} class="mb-2 block text-[13px] font-semibold text-muted">{@label}</span>
        <textarea id={@id} name={@name} class={@class || field_class(@errors)} {@rest}>{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <p :if={@hint} class="mt-2 text-[13px] text-muted text-pretty">{@hint}</p>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="min-w-0">
      <label for={@id} class="block">
        <span :if={@label} class="mb-2 block text-[13px] font-semibold text-muted">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={@class || field_class(@errors)}
          {@rest}
        />
      </label>
      <p :if={@hint} class="mt-2 text-[13px] text-muted text-pretty">{@hint}</p>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  defp field_class(errors) do
    [
      "block h-12 w-full rounded-[14px] border bg-node px-4 text-base text-ink transition-[border-color,box-shadow] duration-200 placeholder:text-subtle focus:outline-none focus:ring-4",
      if(errors == [],
        do: "border-ink/16 focus:border-inverse/40 focus:ring-inverse/10",
        else: "border-danger focus:ring-danger/15"
      )
    ]
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex items-center gap-1.5 text-sm text-danger">
      <.icon name="hero-exclamation-circle-mini" class="size-4" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300", "opacity-0 -translate-y-2",
         "opacity-100 translate-y-0"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0",
         "opacity-0 -translate-y-2"}
    )
  end

  # Dutch versions of the Ecto validation messages this app produces.
  @messages %{
    "can't be blank" => "Vul dit in",
    "is invalid" => "Ongeldige waarde",
    "must be greater than or equal to %{number}" => "Moet minstens %{number} zijn",
    "must be less than or equal to %{number}" => "Mag hoogstens %{number} zijn",
    "another tariff starts on this date" => "Op deze datum begint al een ander tarief"
  }

  @doc """
  Translates an error message to Dutch and fills in its values.
  """
  def translate_error({msg, opts}) do
    Enum.reduce(opts, Map.get(@messages, msg, msg), fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
