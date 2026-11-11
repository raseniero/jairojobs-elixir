defmodule JairojobsWeb.Employer.ListingLive.Show do
  @moduledoc """
  The owner's view of one listing (spec 003 — REQ-003-10): a status box that
  says where the listing stands and offers only the actions that status
  allows, then the listing as visitors will see it once it is Live.

  Submit, withdraw, close and delete all go through `Jairojobs.Listings`,
  which re-checks ownership and status every time (REQ-003-6 to REQ-003-12).
  """
  use JairojobsWeb, :live_view

  import JairojobsWeb.ListingComponents

  alias Jairojobs.Listings

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.link
        navigate={~p"/my/listings"}
        id="back-to-listings"
        class="inline-flex min-h-11 items-center gap-1 text-sm text-primary hover:underline"
      >
        <.icon name="hero-arrow-left" class="size-4" /> My listings
      </.link>

      <section
        id="listing-status-box"
        aria-label="Listing status"
        class="space-y-3 rounded-md border border-base-300 bg-base-200 p-3"
      >
        <div class="flex flex-wrap items-center gap-2">
          <.status_badge listing={@listing} />
          <span class="text-sm font-semibold">— {headline(@listing.status)}</span>
        </div>

        <p class="text-sm">{next_step(@listing.status, @missing)}</p>

        <p
          :if={@missing != [] and @listing.status in [:draft, :rejected]}
          id="listing-missing"
          class="text-sm"
        >
          <span class="font-semibold">Still needed:</span> {missing_labels(@missing)}
        </p>

        <div
          :if={@listing.status == :rejected and @listing.rejection_reason}
          id="listing-rejection-reason"
          class="rounded-md border border-error/40 bg-base-100 p-3 text-sm"
        >
          <p class="font-semibold">What needs changing</p>
          <p class="break-words whitespace-pre-line">{@listing.rejection_reason}</p>
        </div>

        <div :if={@listing.status in [:draft, :rejected]} class="flex flex-wrap items-center gap-3">
          <.button
            id="submit-listing"
            variant="accent"
            phx-click="submit"
            phx-disable-with="Sending…"
          >
            {if @listing.status == :rejected, do: "Resubmit", else: "Submit for approval"}
          </.button>
          <.button navigate={~p"/my/listings/#{@listing.id}/edit"} id="edit-listing">Edit</.button>
          <.button
            id="delete-listing"
            phx-click="delete"
            data-confirm="Delete this listing? This can't be undone."
          >
            Delete
          </.button>
        </div>

        <div :if={@listing.status == :pending}>
          <.button id="withdraw-listing" phx-click="withdraw">Withdraw</.button>
        </div>

        <div :if={@listing.status == :published}>
          <.button
            id="close-listing"
            phx-click="close"
            data-confirm="Close this listing? It will no longer be public and it can't be reopened."
          >
            Close listing
          </.button>
        </div>
      </section>

      <.listing_detail
        listing={@listing}
        business_name={@business_name}
        business_about={@business_about}
      />
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    listing = Listings.get_my_listing!(socket.assigns.current_scope, id)
    {:ok, assign_listing(socket, listing)}
  end

  @impl true
  def handle_event("submit", _params, socket) do
    case Listings.submit_listing(socket.assigns.current_scope, socket.assigns.listing) do
      {:ok, listing} ->
        {:noreply,
         socket
         |> put_flash(:info, "Submitted. An admin will check it before it goes live.")
         |> assign_listing(listing)}

      {:error, reason} ->
        {:noreply, refused(socket, submit_refusal(reason))}
    end
  end

  def handle_event("withdraw", _params, socket) do
    transition(socket, &Listings.withdraw_listing/2, "Withdrawn. It is a draft again.")
  end

  def handle_event("close", _params, socket) do
    transition(socket, &Listings.close_listing/2, "Listing closed.")
  end

  def handle_event("delete", _params, socket) do
    case Listings.delete_listing(socket.assigns.current_scope, socket.assigns.listing) do
      {:ok, _listing} ->
        {:noreply,
         socket
         |> put_flash(:info, "Listing deleted.")
         |> push_navigate(to: ~p"/my/listings")}

      {:error, :locked} ->
        {:noreply, refused(socket, "This listing can't be deleted.")}

      {:error, _gone} ->
        {:noreply, gone(socket)}
    end
  end

  defp transition(socket, fun, message) do
    case fun.(socket.assigns.current_scope, socket.assigns.listing) do
      {:ok, listing} ->
        {:noreply, socket |> put_flash(:info, message) |> assign_listing(listing)}

      {:error, :invalid_status} ->
        {:noreply, refused(socket, "That is no longer possible for this listing.")}

      {:error, _gone} ->
        {:noreply, gone(socket)}
    end
  end

  # Show the reason, and the listing as it is stored now (it may have changed elsewhere).
  defp refused(socket, :gone), do: gone(socket)

  defp refused(socket, message) do
    listing = Listings.get_my_listing!(socket.assigns.current_scope, socket.assigns.listing.id)
    socket |> put_flash(:error, message) |> assign_listing(listing)
  end

  defp gone(socket) do
    socket
    |> put_flash(:error, "That listing is not available.")
    |> push_navigate(to: ~p"/my/listings")
  end

  defp submit_refusal({:incomplete, fields}),
    do: "Not submitted yet. Still needed: #{missing_labels(fields)}."

  defp submit_refusal(:region_hidden),
    do: "This region is no longer available. Edit the listing and choose another region."

  defp submit_refusal(:limit_reached),
    do: "You can have 3 open listings at a time. You can close or withdraw one to post another."

  defp submit_refusal(:invalid_status), do: "This listing has already been submitted."
  defp submit_refusal(_not_found_or_unauthorized), do: :gone

  # A Draft or Rejected listing shows the account's current business details (what
  # would be submitted); any other status shows the copy taken at submit (REQ-003-2).
  defp assign_listing(socket, listing) do
    user = socket.assigns.current_scope.user

    {name, about} =
      if listing.status in [:draft, :rejected],
        do: {user.business_name, user.business_about},
        else: {listing.business_name, listing.business_about}

    socket
    |> assign(:page_title, listing.title)
    |> assign(:listing, listing)
    |> assign(:missing, Listings.missing_fields(listing))
    |> assign(business_name: name, business_about: about)
  end

  defp headline(:draft), do: "only you can see this"
  defp headline(:pending), do: "not public yet"
  defp headline(:published), do: "everyone can see this"
  defp headline(:rejected), do: "not public"
  defp headline(:closed), do: "no longer public"
  defp headline(:taken_down), do: "no longer public"

  defp next_step(:draft, []),
    do: "Submit it and an admin will check it before it goes live."

  defp next_step(:draft, _missing),
    do: "Finish it, then submit it. An admin will check it before it goes live."

  defp next_step(:pending, _missing),
    do:
      "An admin will check it before it goes live. It can't be edited while it waits — " <>
        "withdraw it to make changes."

  defp next_step(:published, _missing),
    do: "It can't be edited while it is live. Close it when the job is filled."

  defp next_step(:rejected, _missing),
    do: "An admin asked for changes. Edit the listing, then resubmit it."

  defp next_step(:closed, _missing),
    do: "You closed this listing. It can't be reopened — to hire again, post a new job."

  defp next_step(:taken_down, _missing),
    do: "jairojobs took this listing down. It can't be edited or reopened."

  @missing_labels %{
    region: "Region",
    area: "Area",
    salary: "Salary",
    employment_type: "Type",
    description: "About the job (at least 50 characters)"
  }

  defp missing_labels(fields), do: Enum.map_join(fields, ", ", &Map.fetch!(@missing_labels, &1))
end
