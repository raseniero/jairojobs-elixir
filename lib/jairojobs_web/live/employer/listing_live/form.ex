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
            Shown on the listing. Needed before you can submit it.
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
