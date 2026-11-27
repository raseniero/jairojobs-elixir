defmodule JairojobsWeb.ListingComponents do
  @moduledoc """
  Components for showing a Listing (spec 003; reused by specs 004 and 005).
  """
  use Phoenix.Component

  import JairojobsWeb.CoreComponents, only: [input: 1]

  alias JairojobsWeb.Format

  @status_labels %{
    draft: "Draft",
    pending: "Waiting for approval",
    published: "Published",
    rejected: "Needs changes",
    closed: "Closed",
    taken_down: "Taken down"
  }

  @doc """
  The words an owner sees for a listing status (spec 003, lifecycle table).
  """
  def status_label(status), do: Map.fetch!(@status_labels, status)

  @employment_type_labels [
    full_time: "Full-time",
    part_time: "Part-time",
    contract: "Contract",
    temporary: "Temporary",
    internship: "Internship"
  ]

  @doc """
  The words shown for an employment type, e.g. `:full_time` → "Full-time".
  """
  def employment_type_label(type), do: Keyword.fetch!(@employment_type_labels, type)

  @doc """
  `{label, value}` pairs for the employment type select.
  """
  def employment_type_options do
    for {type, label} <- @employment_type_labels, do: {label, type}
  end

  @doc """
  The inputs of the listing form: title, region, area, salary, type, schedule
  and the three text sections (REQ-003-4).

  Used by the Employer's form (spec 003) and the Admin edit form (spec 004),
  so the two cannot drift apart. `region_options` is passed in because each
  form decides which regions to offer.
  """
  attr :form, Phoenix.HTML.Form, required: true
  attr :region_options, :list, required: true

  attr :salary_hint, :string,
    default: "Shown on the listing. Needed before you can submit it.",
    doc: "the line under the salary inputs; the Admin edit form says something else"

  def listing_fields(assigns) do
    ~H"""
    <.input
      field={@form[:title]}
      type="text"
      label="Job title"
      maxlength="100"
      placeholder="e.g. Barista (full-time)"
    />

    <.input
      field={@form[:region_id]}
      type="select"
      label="Region"
      prompt="Choose a region"
      options={@region_options}
    />

    <.input
      field={@form[:area]}
      type="text"
      label="Area or neighbourhood"
      maxlength="80"
      placeholder="e.g. Matina, or Remote"
    />

    <fieldset class="space-y-1">
      <legend class="text-sm font-semibold">Salary per month (PHP)</legend>
      <div class="grid grid-cols-2 gap-3">
        <.input
          field={@form[:salary_min]}
          type="text"
          label="From ₱"
          inputmode="numeric"
          autocomplete="off"
          placeholder="14000"
        />
        <.input
          field={@form[:salary_max]}
          type="text"
          label="To ₱"
          inputmode="numeric"
          autocomplete="off"
          placeholder="16000"
        />
      </div>
      <p class="text-xs text-base-content/70">
        {@salary_hint}
      </p>
    </fieldset>

    <.input
      field={@form[:employment_type]}
      type="select"
      label="Type"
      prompt="Choose a type"
      options={employment_type_options()}
    />

    <.input
      field={@form[:schedule]}
      type="text"
      label="Schedule (optional)"
      maxlength="80"
      placeholder="e.g. Shifting, 6 days"
    />

    <.input
      field={@form[:description]}
      type="textarea"
      label="About the job"
      rows="6"
      maxlength="5000"
    />
    <.input
      field={@form[:requirements]}
      type="textarea"
      label="Requirements (optional)"
      rows="4"
      maxlength="3000"
    />
    <.input
      field={@form[:benefits]}
      type="textarea"
      label="Benefits (optional)"
      rows="4"
      maxlength="3000"
    />
    """
  end

  @doc """
  A listing's status as a pill. The status is always written out in words;
  colour only reinforces it (design guide §6).
  """
  attr :listing, :map, required: true

  def status_badge(assigns) do
    ~H"""
    <span
      id={"listing-status-#{@listing.id}"}
      class={["badge badge-sm rounded-full whitespace-nowrap", status_class(@listing.status)]}
    >
      {status_label(@listing.status)}
    </span>
    """
  end

  defp status_class(:published), do: "badge-success"
  defp status_class(:pending), do: "badge-warning"
  defp status_class(:rejected), do: "badge-error"
  defp status_class(_status), do: "badge-ghost"

  @doc """
  A listing laid out the way visitors see it: title, business, facts box,
  then the text sections (design guide §4, "Listing detail").

  The trust line (approved badge, posted date, region) only exists once a
  listing is Published. The public page passes it in the `trust` slot, which
  sits under the business name (spec 005, REQ-005-5); the owner's and the
  Admin's views leave the slot out. Parts that are not filled in yet read
  "Not set yet".

  `title_tag` is the heading level of the title. On the public page the title
  is the page's one main heading, `"h1"`; inside the owner's and the Admin's
  views, under their own page furniture, it is `"h2"`, the default. The
  section headings are always one level below it.

  `business_name` / `business_about` are passed in because the caller decides
  which to show: the account's current details for a Draft or Rejected
  listing, the listing's own copy otherwise (REQ-003-2).
  """
  attr :listing, :map, required: true
  attr :business_name, :string, default: nil
  attr :business_about, :string, default: nil
  attr :title_tag, :string, default: "h2", values: ~w(h1 h2)

  slot :trust, doc: "the public page's trust line, shown under the business name"

  def listing_detail(assigns) do
    assigns =
      assign(assigns,
        salary: Format.salary_range(assigns.listing.salary_min, assigns.listing.salary_max),
        location: location(assigns.listing),
        section_tag: if(assigns.title_tag == "h1", do: "h2", else: "h3")
      )

    ~H"""
    <article id="listing-detail" class="space-y-4">
      <header class="space-y-1">
        <.dynamic_tag
          tag_name={@title_tag}
          id="listing-title"
          class="text-[22px] font-bold break-words"
        >
          {@listing.title}
        </.dynamic_tag>
        <p id="listing-business">{@business_name}</p>
        {render_slot(@trust)}
      </header>

      <dl class="grid grid-cols-2 gap-x-4 gap-y-3 rounded-md bg-base-200 p-3 text-sm">
        <.fact id="listing-salary" label="Salary" value={@salary} strong wide />
        <.fact id="listing-location" label="Location" value={@location} />
        <.fact
          id="listing-type"
          label="Type"
          value={@listing.employment_type && employment_type_label(@listing.employment_type)}
        />
        <.fact
          :if={@listing.schedule}
          id="listing-schedule"
          label="Schedule"
          value={@listing.schedule}
        />
      </dl>

      <.text_section tag={@section_tag} title="About the job" text={@listing.description} always />
      <.text_section tag={@section_tag} title="Requirements" text={@listing.requirements} />
      <.text_section tag={@section_tag} title="Benefits" text={@listing.benefits} />
      <.text_section
        :if={@business_name}
        tag={@section_tag}
        title={"About #{@business_name}"}
        text={@business_about}
      />
    </article>
    """
  end

  defp location(%{area: area, region: %{name: region}}) when is_binary(area),
    do: "#{area}, #{region}"

  defp location(%{region: %{name: region}}), do: region
  defp location(%{area: area}) when is_binary(area), do: area
  defp location(_listing), do: nil

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, default: nil
  attr :strong, :boolean, default: false
  attr :wide, :boolean, default: false

  defp fact(assigns) do
    ~H"""
    <div class={@wide && "col-span-2"}>
      <dt class="text-xs text-base-content/70">{@label}</dt>
      <dd id={@id} class={[@strong && "font-semibold", !@value && "text-base-content/60"]}>
        {@value || "Not set yet"}
      </dd>
    </div>
    """
  end

  attr :tag, :string, required: true
  attr :title, :string, required: true
  attr :text, :string, default: nil
  attr :always, :boolean, default: false

  # Plain text only: escaped, with the writer's line breaks kept (REQ-003-4).
  defp text_section(assigns) do
    ~H"""
    <section :if={@text || @always} class="space-y-1">
      <.dynamic_tag tag_name={@tag} class="text-[15px] font-bold">{@title}</.dynamic_tag>
      <p :if={@text} class="break-words whitespace-pre-line">{@text}</p>
      <p :if={!@text} class="text-base-content/60">Not written yet</p>
    </section>
    """
  end
end
