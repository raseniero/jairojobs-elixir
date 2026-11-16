defmodule JairojobsWeb.Admin.ListingLive.Show do
  @moduledoc """
  The Admin's view of one submitted listing (spec 004 — REQ-004-4): a box that
  says where the listing stands, who posted it and what was last decided, then
  the listing as visitors will see it.

  Every action goes through `Jairojobs.Listings`, which checks the role and
  the status again. After a refusal the listing is loaded afresh, so the page
  shows it as it now is.
  """
  use JairojobsWeb, :live_view

  import JairojobsWeb.ListingComponents

  alias Jairojobs.Listings
  alias JairojobsWeb.Format

  # The lists an Admin can have come from, by their value in the address.
  @lists ~w(waiting live needs-changes taken-down closed)

  @region_hidden "Its region is hidden, so it cannot be approved as it is. Show the region " <>
                   "again, move the listing to another region with Edit, or reject it with " <>
                   "a reason."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.link
        navigate={@back_path}
        id="back-to-admin-listings"
        class="inline-flex min-h-11 items-center gap-1 text-sm text-primary hover:underline"
      >
        <.icon name="hero-arrow-left" class="size-4" /> Listings
      </.link>

      <section
        id="moderation-box"
        aria-label="Moderation"
        class="space-y-3 rounded-md border border-base-300 bg-base-200 p-3"
      >
        <div class="flex flex-wrap items-center gap-2">
          <.status_badge listing={@listing} />
          <span
            :if={@own?}
            id="your-listing"
            class="badge badge-ghost badge-sm rounded-full whitespace-nowrap"
          >
            Your listing
          </span>
        </div>

        <dl class="space-y-1 text-sm">
          <div id="listing-poster" class="break-words">
            <dt class="inline text-base-content/70">Posted by</dt>
            <dd class="inline">
              <span class="font-semibold">{@listing.business_name}</span> · {@listing.user.email}
            </dd>
          </div>
          <div :if={@listing.submitted_at} id="listing-submitted">
            Submitted {Format.time_ago(@listing.submitted_at)}
          </div>
          <div :if={@listing.decided_at} id="listing-decision" class="break-words">
            {decision(@listing.status)} {Format.time_ago(@listing.decided_at)}
            <span :if={@listing.decided_by}>by {@listing.decided_by.email}</span>
          </div>
        </dl>

        <div
          :if={decision_reason(@listing)}
          id="listing-decision-reason"
          class="rounded-md border border-base-300 bg-base-100 p-3 text-sm"
        >
          <p class="font-semibold">The reason given to the employer</p>
          <p class="break-words whitespace-pre-line">{decision_reason(@listing)}</p>
        </div>

        <div
          :if={!@listing.region.active}
          id="listing-region-hidden"
          class="rounded-md border border-base-300 bg-base-100 p-3 text-sm"
        >
          <p class="flex flex-wrap items-center gap-2">
            <span class="font-semibold">{@listing.region.name}</span>
            <span class="badge badge-ghost badge-sm rounded-full">hidden</span>
          </p>
          <p :if={@listing.status == :pending}>{@region_hidden}</p>
        </div>

        <p :if={help(@listing.status, @own?)} id="moderation-help" class="text-sm">
          {help(@listing.status, @own?)}
        </p>

        <div :if={@listing.status == :pending} class="flex flex-wrap items-center gap-3">
          <.button
            id="approve-listing"
            variant="accent"
            phx-click="approve"
            phx-disable-with="Approving…"
          >
            Approve
          </.button>
        </div>
      </section>

      <.listing_detail
        listing={@listing}
        business_name={@listing.business_name}
        business_about={@listing.business_about}
      />
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :region_hidden, @region_hidden)}
  end

  # Raises `Ecto.NoResultsError` (a 404) for a Draft, an unknown id or a malformed one.
  @impl true
  def handle_params(%{"id" => id} = params, _uri, socket) do
    listing = Listings.get_listing_for_moderation!(socket.assigns.current_scope, id)

    {:noreply,
     socket
     |> assign(:back_path, list_path(params["from"]))
     |> assign_listing(listing)}
  end

  @impl true
  def handle_event("approve", _params, socket) do
    %{current_scope: scope, listing: listing} = socket.assigns

    case Listings.approve_listing(scope, listing, &owner_url/1) do
      {:ok, _listing, email} ->
        {:noreply,
         socket
         |> put_flash(:info, with_email("Approved. It is live.", email))
         |> push_navigate(to: ~p"/admin/listings")}

      {:error, reason} ->
        {:noreply, refused(socket, reason)}
    end
  end

  # The address of the listing in its owner's My listings, for the email (REQ-004-9).
  defp owner_url(listing), do: url(~p"/my/listings/#{listing.id}")

  defp with_email(message, :failed), do: message <> " The employer could not be emailed."
  defp with_email(message, _sent_or_own_listing), do: message

  defp refusal(:not_pending), do: "This listing is no longer waiting for approval."
  defp refusal(:not_published), do: "This listing is no longer live."
  defp refusal(:not_editable), do: "This listing can no longer be edited."
  defp refusal(:region_hidden), do: @region_hidden
  defp refusal(:not_found), do: "That listing is not available."
  defp refusal(:unauthorized), do: "You are not authorized to do that."

  # Says why, and shows the listing as it is stored now: it has changed elsewhere.
  # A listing an Admin can no longer be shown (withdrawn, so a Draft again, or
  # deleted) sends them to the queue with the message.
  defp refused(socket, :unauthorized) do
    socket |> put_flash(:error, refusal(:unauthorized)) |> push_navigate(to: ~p"/")
  end

  defp refused(socket, reason) do
    %{current_scope: scope, listing: %{id: id}} = socket.assigns
    socket = put_flash(socket, :error, refusal(reason))

    try do
      assign_listing(socket, Listings.get_listing_for_moderation!(scope, id))
    rescue
      Ecto.NoResultsError -> push_navigate(socket, to: ~p"/admin/listings")
    end
  end

  defp assign_listing(socket, listing) do
    socket
    |> assign(:page_title, listing.title)
    |> assign(:listing, listing)
    |> assign(:own?, listing.user_id == socket.assigns.current_scope.user.id)
  end

  defp list_path(from) when from in @lists and from != "waiting",
    do: ~p"/admin/listings?#{[status: from]}"

  defp list_path(_queue_or_unknown), do: ~p"/admin/listings"

  # What the latest decision was follows from the status (plan, Data model).
  defp decision(status) when status in [:published, :closed], do: "Approved"
  defp decision(:rejected), do: "Rejected"
  defp decision(:taken_down), do: "Taken down"

  defp decision_reason(%{status: :rejected, rejection_reason: reason}), do: reason
  defp decision_reason(%{status: :taken_down, takedown_reason: reason}), do: reason
  defp decision_reason(_listing), do: nil

  # One plain sentence on what the offered action will do (REQ-004-4). Nobody is
  # emailed about their own action, so the Admin's own listing does not say so.
  defp help(:pending, false), do: "Approving makes it public and emails the employer."
  defp help(:pending, true), do: "Approving makes it public."

  defp help(:published, false),
    do: "Taking it down removes it from public view for good and emails the employer."

  defp help(:published, true), do: "Taking it down removes it from public view for good."
  defp help(_status, _own?), do: nil
end
