defmodule JairojobsWeb.Admin.ListingLive.Form do
  @moduledoc """
  An Admin's fix to a Waiting or Published listing (spec 004 — REQ-004-8): the
  Employer's listing form, plus this listing's own copy of the business name
  and "about".

  Meant for small fixes. The listing must stay complete, its status does not
  change, and its owner is emailed the names of the parts that changed.
  """
  use JairojobsWeb, :live_view

  import JairojobsWeb.ListingComponents

  alias Jairojobs.Listings
  alias Jairojobs.Listings.Listing
  alias Jairojobs.Regions

  # The lists an Admin can have come from, by their value in the address.
  @lists ~w(waiting published needs-changes taken-down closed)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <h1 class="text-[22px] font-bold">Edit listing</h1>

      <p id="admin-edit-note" class="text-sm">
        For small fixes: a typo, a wrong area, stray formatting.
        <span class="font-semibold">The employer will be told what you changed.</span>
      </p>

      <.form
        for={@form}
        id="listing-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
        <.listing_fields
          form={@form}
          region_options={@region_options}
          salary_hint="Shown on the listing. A listing always states its salary."
        />

        <.input field={@form[:business_name]} type="text" label="Business name" maxlength="80" />
        <.input
          field={@form[:business_about]}
          type="textarea"
          label="About the business (optional)"
          rows="3"
          maxlength="500"
        />

        <p class="text-xs text-base-content/70">
          The business name and “about” change on this listing only, not on the
          employer's account.
        </p>

        <div class="flex items-center gap-4">
          <.button variant="accent" phx-disable-with="Saving…">Save changes</.button>
          <.link
            navigate={@show_path}
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

  # Raises `Ecto.NoResultsError` (a 404) for a Draft, an unknown id or a malformed one.
  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    listing = Listings.get_listing_for_moderation!(socket.assigns.current_scope, id)
    from = if params["from"] in @lists, do: params["from"]
    socket = assign(socket, from: from, show_path: show_path(listing, from))

    if listing.status in [:pending, :published] do
      {:ok,
       socket
       |> assign(page_title: "Edit listing", listing: listing)
       |> assign(:region_options, region_options(listing))
       |> assign_form(Listings.change_listing_as_admin(listing))}
    else
      # A stale link or a typed address: no form for a listing that cannot be edited.
      {:ok,
       socket
       |> put_flash(:error, refusal(:not_editable))
       |> push_navigate(to: show_path(listing, from))}
    end
  end

  @impl true
  def handle_event("validate", %{"listing" => params}, socket) do
    changeset = Listings.change_listing_as_admin(socket.assigns.listing, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"listing" => params}, socket) do
    %{current_scope: scope, listing: listing, show_path: show_path} = socket.assigns

    case Listings.update_listing_as_admin(scope, listing, params, &owner_url/1) do
      {:ok, _listing, :unchanged} ->
        {:noreply,
         socket |> put_flash(:info, "Nothing was changed.") |> push_navigate(to: show_path)}

      {:ok, _listing, email} ->
        {:noreply,
         socket
         |> put_flash(:info, with_email("Changes saved.", email))
         |> push_navigate(to: show_path)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, reason} ->
        {:noreply, refused(socket, reason)}
    end
  end

  # The address of the listing in its owner's My listings, for the email (REQ-004-9).
  defp owner_url(listing), do: url(~p"/my/listings/#{listing.id}")

  defp with_email(message, :failed), do: message <> " The employer could not be emailed."
  defp with_email(message, _sent_or_own_listing), do: message

  defp refusal(:not_editable), do: "This listing can no longer be edited."
  defp refusal(:not_found), do: "That listing is not available."
  defp refusal(:unauthorized), do: "You are not authorized to do that."

  defp refused(socket, :unauthorized) do
    socket |> put_flash(:error, refusal(:unauthorized)) |> push_navigate(to: ~p"/")
  end

  # Back to the Admin view, which shows the listing as it now is. A listing an
  # Admin can no longer be shown (withdrawn, so a Draft again, or deleted) sends
  # them to the queue with the message.
  defp refused(socket, reason) do
    %{current_scope: scope, listing: %{id: id}, show_path: show_path} = socket.assigns
    socket = put_flash(socket, :error, refusal(reason))

    try do
      _still_visible = Listings.get_listing_for_moderation!(scope, id)
      push_navigate(socket, to: show_path)
    rescue
      Ecto.NoResultsError -> push_navigate(socket, to: ~p"/admin/listings")
    end
  end

  defp show_path(%Listing{id: id}, nil), do: ~p"/admin/listings/#{id}"
  defp show_path(%Listing{id: id}, from), do: ~p"/admin/listings/#{id}?#{[from: from]}"

  # Active regions, plus the listing's own region if it has been hidden: it may
  # stay where it is, but no other hidden region can be chosen (REQ-004-8).
  defp region_options(%Listing{} = listing) do
    active = for region <- Regions.list_active_regions(), do: {region.name, region.id}

    case listing.region do
      %{active: false} = region -> active ++ [{"#{region.name} (hidden)", region.id}]
      _active -> active
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
