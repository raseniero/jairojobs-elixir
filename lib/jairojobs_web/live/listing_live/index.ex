defmodule JairojobsWeb.ListingLive.Index do
  @moduledoc """
  The public lists of jobs (spec 005): the home page, which lists the
  Published listings of every region (REQ-005-2), and each region's own list
  at `/jobs/<region slug>` (REQ-005-3). One LiveView, so choosing a region
  changes the list without loading a new page.

  The address is the state: the region, the words searched, the type of work
  (REQ-005-4), and how far the list is opened with "Show more". Everything the
  page shows is read from it in `handle_params/3`, so an address opened again,
  or reached with the browser's back button, gives the same list, opened as
  far as it was (plan decision 9). Searching, choosing a type, choosing a
  region and "Show more" only ever change the address.

  What may be listed is not decided here: `Jairojobs.Listings.list_public_listings/1`
  returns Published listings and nothing else (REQ-005-1). The page is the same
  for a visitor and for anyone logged in; only the menu differs.
  """
  use JairojobsWeb, :live_view

  alias Jairojobs.Listings
  alias Jairojobs.Listings.Listing
  alias Jairojobs.Regions
  alias JairojobsWeb.Format
  alias JairojobsWeb.ListingComponents
  alias JairojobsWeb.PublicAddress

  # Rows come 20 at a time (spec decision 9). The address remembers how far the list is
  # opened up to 200 rows; past that "Show more" still adds rows, but the address stays.
  @step 20
  @most_in_address 200

  # A type of work as an address writes it ("part-time"), its value and its label.
  @types for type <- Listing.employment_types(),
             do:
               {type |> Atom.to_string() |> String.replace("_", "-"), type,
                ListingComponents.employment_type_label(type)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="jobs" class="space-y-3">
        <%!-- The choices are "All regions" and the active regions. A hidden region is never
             offered, though its own address still opens (REQ-005-3). The row scrolls inside
             itself when it is wider than the phone; the page does not. --%>
        <nav id="region-choices" aria-label="Regions" class="-mx-4 overflow-x-auto px-4">
          <ul class="flex w-max gap-2">
            <%!-- "All regions" comes first: it is the one chosen on the home page, and at
                 the end of a row wider than the phone it would start off the screen. --%>
            <li>
              <.region_choice
                id="region-choice-all"
                path={PublicAddress.list_path(nil, @narrowed)}
                chosen={@region == nil}
                label="All regions"
              />
            </li>
            <li :for={choice <- @regions}>
              <.region_choice
                id={"region-choice-#{choice.slug}"}
                path={PublicAddress.list_path(choice, @narrowed)}
                chosen={@region != nil and @region.id == choice.id}
                label={choice.name}
              />
            </li>
          </ul>
        </nav>

        <%!-- A region's list names its region once, here, so its rows need not. The home
             page has no headline above the list (spec decision 7); its heading is for
             screen readers. --%>
        <h1 :if={@region} id="jobs-heading" class="text-[22px] font-bold break-words">
          Jobs in {@region.name}
        </h1>
        <h1 :if={!@region} id="jobs-heading" class="sr-only">Jobs in the Philippines</h1>

        <%!-- An ordinary GET form that asks for this same list, so it works before the live
             connection is up; once it is, the LiveView changes the address itself. Typing
             does not search: "Search" does, and so does choosing a type (REQ-005-4). --%>
        <.form
          for={@form}
          id="search-form"
          method="get"
          action={PublicAddress.list_path(@region)}
          phx-submit="search"
          phx-change="filter"
          class="space-y-2"
        >
          <div class="flex items-start gap-2">
            <div class="min-w-0 flex-1">
              <.input
                field={@form[:search]}
                id="search-words"
                type="search"
                aria-label="Search jobs"
                maxlength="100"
                autocomplete="off"
                enterkeyhint="search"
              />
            </div>
            <%!-- Primary, not accent: no public screen in spec 005 has an accent action. --%>
            <.button id="search-submit" variant="primary" class="btn btn-primary mt-1 min-h-11">
              Search
            </.button>
          </div>
          <.input
            field={@form[:type]}
            id="search-type"
            type="select"
            aria-label="Type of work"
            options={type_options()}
          />
        </.form>

        <div :if={@total > 0} class="flex flex-wrap items-center justify-between gap-x-4">
          <p id="jobs-count" class="text-xs text-base-content/70">
            {count(@total, @region)} · newest first
          </p>
          <.clear_search :if={@narrowed?} region={@region} />
        </div>

        <div
          :if={@total > 0}
          id="job-rows"
          phx-update="stream"
          class="divide-y divide-base-300 border-y border-base-300"
        >
          <.link
            :for={{dom_id, listing} <- @streams.listings}
            id={dom_id}
            href={PublicAddress.listing_path(listing)}
            class="block min-h-11 py-3 transition-colors hover:bg-base-200 focus-visible:bg-base-200"
          >
            <h2 class="text-[17px] leading-snug font-semibold break-words text-primary">
              {listing.title}
            </h2>
            <p class="mt-0.5 break-words">{listing.business_name} · {where(listing, @region)}</p>
            <p class="mt-1 flex flex-wrap items-center gap-x-2.5 gap-y-1 text-sm text-base-content/70">
              <span class="font-semibold text-base-content">
                {Format.salary_range(listing.salary_min, listing.salary_max, :short)}
              </span>
              <span>{Format.time_ago(listing.published_at)}</span>
              <span class="rounded-full border border-success/40 px-2 text-xs font-semibold whitespace-nowrap text-success">
                ✓ Approved
              </span>
            </p>
          </.link>
        </div>

        <%!-- Up to 200 rows this is a real link to the same list opened 20 rows further. It
             replaces the address, so Back never has to be pressed once per "Show more".
             Past 200 the address stays, and a button adds the rows where they are. --%>
        <div :if={@loaded < @total}>
          <.link
            :if={@next_shown}
            id="show-more"
            patch={PublicAddress.list_path(@region, @narrowed ++ [shown: @next_shown])}
            replace
            class="btn min-h-11 border border-base-300 btn-ghost"
          >
            Show more
          </.link>
          <.button :if={!@next_shown} id="show-more" phx-click="more">Show more</.button>
        </div>

        <div :if={@total == 0} class="py-3">
          <p id="no-jobs" class="text-base-content/70">{nothing(@region, @narrowed?)}</p>
          <%!-- Links of their own, not inside the sentence, so each is 44 px tall. --%>
          <.clear_search :if={@narrowed?} region={@region} />
          <.link
            :if={@region && !@narrowed?}
            patch={PublicAddress.list_path(nil)}
            id="see-all-regions"
            class="inline-flex min-h-11 items-center text-primary hover:underline"
          >
            See all regions
          </.link>
        </div>

        <p id="trust-line" class="pt-2 text-xs text-base-content/70">
          Every listing shows salary and is checked by jairojobs before it is published.
        </p>
      </section>
    </Layouts.app>
    """
  end

  attr :region, :any, required: true

  # Leads to the same list with no words and no type. Shown whenever either is set.
  defp clear_search(assigns) do
    ~H"""
    <.link
      patch={PublicAddress.list_path(@region)}
      id="clear-search"
      class="inline-flex min-h-11 items-center text-primary hover:underline"
    >
      Clear search
    </.link>
    """
  end

  attr :id, :string, required: true
  attr :path, :string, required: true
  attr :label, :string, required: true
  attr :chosen, :boolean, required: true

  # One region choice: a pill, 44 px tall. The chosen one is filled, and marked for
  # screen readers as well as by colour (spec 005, accessibility).
  defp region_choice(assigns) do
    ~H"""
    <.link
      patch={@path}
      id={@id}
      aria-current={@chosen && "page"}
      class={[
        "inline-flex min-h-11 items-center rounded-full border px-3.5 text-sm whitespace-nowrap",
        "transition-colors",
        @chosen && "border-primary bg-primary text-primary-content",
        !@chosen && "border-base-300 bg-base-100 hover:bg-base-200"
      ]}
    >
      {@label}
    </.link>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:regions, Regions.list_active_regions())
     # A row's DOM id is made from its address, never from the listing's id, so no id
     # appears in a public page (plan decision 17). The two slugs are joined by a double
     # hyphen, which no slug contains, so two different addresses cannot make one id.
     |> stream_configure(:listings, dom_id: &"job-#{&1.region.slug}--#{&1.slug}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    region = region(socket.assigns.live_action, params)
    search = Listings.search_words(params["search"])
    {type_param, type} = type(params["type"])
    shown = shown(params["shown"])

    # What the list is: these three, and nothing else, decide which listings are on it.
    list = [region: region, search: search, type: type]

    {:noreply,
     socket
     |> assign(:page_title, page_title(region))
     |> assign(:region, region)
     # What narrows the list, as the address carries it; the region choices keep it.
     |> assign(:narrowed, search: search, type: type_param)
     |> assign(:narrowed?, search != nil or type != nil)
     |> assign(:form, to_form(%{"search" => search, "type" => type_param}))
     |> load(list, shown)}
  end

  # The same list, opened further: only the rows that are not on the page yet are
  # fetched, and they go under the ones already there. This is "Show more".
  defp load(%{assigns: %{list: list, loaded: loaded}} = socket, list, shown)
       when shown > loaded do
    {listings, total} =
      Listings.list_public_listings(list ++ [offset: loaded, limit: shown - loaded])

    socket
    |> assign(total: total, loaded: loaded + length(listings), next_shown: next_shown(shown))
    |> stream(:listings, listings)
  end

  # Any other list, or the page as first opened: the first `shown` rows, replacing
  # whatever was there.
  defp load(socket, list, shown) do
    {listings, total} = Listings.list_public_listings(list ++ [limit: shown])

    socket
    |> assign(list: list, total: total, loaded: length(listings), next_shown: next_shown(shown))
    |> stream(:listings, listings, reset: true)
  end

  # How many rows the address asks for: 20, 40, … up to 200. Anything else in the
  # address (nothing, nonsense, a number between two steps) goes down to a step.
  defp shown(param) when is_binary(param) do
    case Integer.parse(param) do
      {number, ""} ->
        number |> div(@step) |> Kernel.*(@step) |> max(@step) |> min(@most_in_address)

      _not_a_number ->
        @step
    end
  end

  defp shown(_none), do: @step

  # The address "Show more" leads to, or `nil` once the address keeps no more.
  defp next_shown(shown) when shown < @most_in_address, do: shown + @step
  defp next_shown(_shown), do: nil

  # "Search", or Enter in the field.
  @impl true
  def handle_event("search", params, socket), do: {:noreply, narrow(socket, params)}

  # The form changed. Only a chosen type applies at once; typing waits for "Search".
  def handle_event("filter", %{"_target" => ["type"]} = params, socket),
    do: {:noreply, narrow(socket, params)}

  def handle_event("filter", _typing, socket), do: {:noreply, socket}

  # "Show more" past the 200 rows the address keeps: 20 more, where they are.
  def handle_event("more", _params, socket) do
    %{list: list, loaded: loaded} = socket.assigns
    {listings, total} = Listings.list_public_listings(list ++ [offset: loaded, limit: @step])

    {:noreply,
     socket
     |> assign(total: total, loaded: loaded + length(listings))
     |> stream(:listings, listings)}
  end

  # Everything a search does is to change the address; `handle_params/3` does the rest.
  # The words and the type are cleaned here as they are there, so what cannot be
  # searched for never reaches the address.
  defp narrow(socket, params) do
    {type_param, _type} = type(params["type"])

    push_patch(socket,
      to:
        PublicAddress.list_path(socket.assigns.region,
          search: Listings.search_words(params["search"]),
          type: type_param
        )
    )
  end

  # A type as the address writes it, and its value. Anything else is no type at all.
  defp type(param) do
    case List.keyfind(@types, param, 0) do
      {param, type, _label} -> {param, type}
      nil -> {nil, nil}
    end
  end

  defp type_options,
    do: [{"Any type", ""} | for({param, _type, label} <- @types, do: {label, param})]

  # The home page is every region. A region's list is found by its slug, hidden or
  # not; an unknown slug raises, which is "not found" (REQ-005-3).
  defp region(:all, _params), do: nil
  defp region(:region, %{"region" => slug}), do: Regions.get_region_by_slug!(slug)

  defp page_title(nil), do: "Jobs in the Philippines, with the salary shown"
  defp page_title(region), do: "Jobs in #{region.name}"

  defp nothing(_region, true), do: "No jobs match your search."
  defp nothing(nil, false), do: "No jobs are listed yet."
  defp nothing(region, false), do: "No jobs are listed in #{region.name} yet."

  defp count(total, nil), do: jobs(total)
  defp count(total, region), do: "#{jobs(total)} in #{region.name}"

  defp jobs(1), do: "1 job"
  defp jobs(total), do: "#{total} jobs"

  # On the list of every region a row names the region after the area (REQ-005-2);
  # on a region's own list the heading has already named it (REQ-005-3).
  defp where(listing, nil), do: "#{listing.area}, #{listing.region.name}"
  defp where(listing, _region), do: listing.area
end
