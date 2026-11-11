defmodule JairojobsWeb.ListingComponents do
  @moduledoc """
  Components for showing a Listing (spec 003; reused by specs 004 and 005).
  """
  use Phoenix.Component

  alias JairojobsWeb.Format

  @status_labels %{
    draft: "Draft",
    pending: "Waiting for approval",
    published: "Live",
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

  The trust line (approved badge, posted date) is not part of this component:
  it only exists once a listing is Live and is added by the public page
  (spec 005). Parts that are not filled in yet read "Not set yet".

  `business_name` / `business_about` are passed in because the caller decides
  which to show: the account's current details for a Draft or Rejected
  listing, the listing's own copy otherwise (REQ-003-2).
  """
  attr :listing, :map, required: true
  attr :business_name, :string, default: nil
  attr :business_about, :string, default: nil

  def listing_detail(assigns) do
    assigns =
      assign(assigns,
        salary: Format.salary_range(assigns.listing.salary_min, assigns.listing.salary_max),
        location: location(assigns.listing)
      )

    ~H"""
    <article id="listing-detail" class="space-y-4">
      <header class="space-y-1">
        <h2 id="listing-title" class="text-[22px] font-bold break-words">{@listing.title}</h2>
        <p id="listing-business">{@business_name}</p>
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

      <.text_section title="About the job" text={@listing.description} always />
      <.text_section title="Requirements" text={@listing.requirements} />
      <.text_section title="Benefits" text={@listing.benefits} />
      <.text_section :if={@business_name} title={"About #{@business_name}"} text={@business_about} />
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

  attr :title, :string, required: true
  attr :text, :string, default: nil
  attr :always, :boolean, default: false

  # Plain text only: escaped, with the writer's line breaks kept (REQ-003-4).
  defp text_section(assigns) do
    ~H"""
    <section :if={@text || @always} class="space-y-1">
      <h3 class="text-[15px] font-bold">{@title}</h3>
      <p :if={@text} class="break-words whitespace-pre-line">{@text}</p>
      <p :if={!@text} class="text-base-content/60">Not written yet</p>
    </section>
    """
  end
end
