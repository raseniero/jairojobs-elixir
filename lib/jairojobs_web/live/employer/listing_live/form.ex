defmodule JairojobsWeb.Employer.ListingLive.Form do
  @moduledoc """
  Write (`:new`) or change (`:edit`) a listing (spec 003 — REQ-003-3,
  REQ-003-5). Layout per `wireframe-posting`.

  A draft can be saved with only a title; the rest is checked when the listing
  is submitted. Only Draft and Rejected listings can be edited.
  """
  use JairojobsWeb, :live_view

  import JairojobsWeb.ListingComponents

  alias Jairojobs.Accounts
  alias Jairojobs.Listings
  alias Jairojobs.Listings.Listing
  alias Jairojobs.Regions

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <h1 class="text-[22px] font-bold">{@page_title}</h1>

      <.form
        for={@form}
        id="listing-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
        <.listing_fields form={@form} region_options={@region_options} />

        <p class="text-xs text-base-content/70">
          You can save now and finish later. Nothing is public until you submit it and an admin
          approves it.
        </p>

        <div class="flex items-center gap-4">
          <.button variant="accent" phx-disable-with="Saving…">{@submit_label}</.button>
          <.link
            navigate={@cancel_path}
            id="listing-form-cancel"
            class="inline-flex min-h-11 items-center text-primary hover:underline"
          >
            Cancel
          </.link>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  # REQ-003-2: business details come before the first listing.
  defp apply_action(socket, :new, _params) do
    if Accounts.business_details?(socket.assigns.current_scope.user) do
      socket
      |> assign(page_title: "Post a job", submit_label: "Save draft")
      |> assign(:cancel_path, ~p"/my/listings")
      |> assign_listing(%Listing{})
    else
      push_navigate(socket, to: ~p"/my/business")
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    listing = Listings.get_my_listing!(socket.assigns.current_scope, id)

    if listing.status in [:draft, :rejected] do
      socket
      |> assign(page_title: "Edit listing", submit_label: "Save changes")
      |> assign(:cancel_path, show_path(listing))
      |> assign_listing(listing)
    else
      locked(socket, listing)
    end
  end

  defp assign_listing(socket, listing) do
    socket
    |> assign(:listing, listing)
    |> assign(:region_options, region_options(listing))
    |> assign_form(Listings.change_listing(listing))
  end

  @impl true
  def handle_event("validate", %{"listing" => params}, socket) do
    changeset = Listings.change_listing(socket.assigns.listing, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"listing" => params}, socket) do
    case save(socket, socket.assigns.live_action, params) do
      {:ok, listing} ->
        {:noreply,
         socket
         |> put_flash(:info, saved_message(socket.assigns.live_action))
         |> push_navigate(to: show_path(listing))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :locked} ->
        {:noreply, locked(socket, socket.assigns.listing)}

      {:error, :business_details_required} ->
        {:noreply, push_navigate(socket, to: ~p"/my/business")}

      {:error, reason} when reason in [:not_found, :unauthorized] ->
        {:noreply,
         socket
         |> put_flash(:error, "That listing is not available.")
         |> push_navigate(to: ~p"/my/listings")}
    end
  end

  defp save(socket, :new, params) do
    Listings.create_listing(socket.assigns.current_scope, params)
  end

  defp save(socket, :edit, params) do
    Listings.update_listing(socket.assigns.current_scope, socket.assigns.listing, params)
  end

  defp saved_message(:new), do: "Draft saved."
  defp saved_message(:edit), do: "Changes saved."

  defp locked(socket, listing) do
    socket
    |> put_flash(:error, "This listing can't be edited while it is #{locked_reason(listing)}.")
    |> push_navigate(to: show_path(listing))
  end

  defp locked_reason(%Listing{status: :pending}), do: "waiting for approval"
  defp locked_reason(%Listing{status: :published}), do: "live"
  defp locked_reason(%Listing{status: :closed}), do: "closed"
  defp locked_reason(%Listing{status: :taken_down}), do: "taken down"
  defp locked_reason(%Listing{}), do: "locked"

  defp show_path(%Listing{id: id}), do: ~p"/my/listings/#{id}"

  # Active regions, plus the listing's own region if an Admin has hidden it since:
  # editing must never silently clear it. Submitting then asks for another region.
  defp region_options(%Listing{} = listing) do
    active = for region <- Regions.list_active_regions(), do: {region.name, region.id}

    case listing.region do
      %{active: false} = region ->
        active ++ [{"#{region.name} (no longer available)", region.id}]

      _none_or_active ->
        active
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
