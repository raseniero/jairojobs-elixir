defmodule JairojobsWeb.Admin.RegionLive.Form do
  @moduledoc """
  Add (`:new`) or rename (`:edit`) a region (spec 002 — REQ-002-2, REQ-002-3).
  Layout per `wireframe-regions-admin`. The web address is derived from the
  name once, when the region is added, and is read-only afterwards.
  """
  use JairojobsWeb, :live_view

  alias Jairojobs.Regions
  alias Jairojobs.Regions.Region

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <nav aria-label="Breadcrumb" class="text-sm text-base-content/70">
        <.link navigate={~p"/admin"} id="breadcrumb-admin" class="text-primary hover:underline">
          Admin
        </.link>
        <span aria-hidden="true">▸</span>
        <.link
          navigate={~p"/admin/regions"}
          id="breadcrumb-regions"
          class="text-primary hover:underline"
        >
          Regions
        </.link>
        <span aria-hidden="true">▸</span>
        <span class="font-semibold text-base-content">{@crumb}</span>
      </nav>

      <h1 class="text-[22px] font-bold">{@page_title}</h1>

      <.form
        for={@form}
        id="region-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
        <.input
          field={@form[:name]}
          type="text"
          label="Name"
          maxlength="80"
          autocomplete="off"
          phx-mounted={JS.focus()}
        />

        <div :if={@live_action == :new} class="text-sm text-base-content/70">
          <p>We'll make the web address from the name:</p>
          <p id="region-address" class="font-mono text-base-content">/jobs/{@slug || "…"}</p>
        </div>

        <div :if={@live_action == :edit} class="rounded-md bg-base-200 p-3 text-sm">
          <p class="font-semibold">Web address</p>
          <p id="region-address" class="font-mono">/jobs/{@slug}</p>
          <p class="text-base-content/70">
            The address never changes, so shared links keep working.
          </p>
        </div>

        <div class="flex items-center gap-4">
          <.button variant="accent" phx-disable-with="Saving…">{@submit_label}</.button>
          <.link
            navigate={~p"/admin/regions"}
            id="region-form-cancel"
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

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(page_title: "Add a region", crumb: "New", submit_label: "Add region")
    |> assign(:region, %Region{})
    |> assign_form(Regions.change_region(%Region{}))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    region = Regions.get_region!(id)

    socket
    |> assign(page_title: "Edit region", crumb: "Edit", submit_label: "Save")
    |> assign(:region, region)
    |> assign_form(Regions.change_region(region))
  end

  @impl true
  def handle_event("validate", %{"region" => params}, socket) do
    changeset = Regions.change_region(socket.assigns.region, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"region" => params}, socket) do
    case save(socket, socket.assigns.live_action, params) do
      {:ok, _region} ->
        {:noreply,
         socket
         |> put_flash(:info, saved_message(socket.assigns.live_action))
         |> push_navigate(to: ~p"/admin/regions")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, "You are not authorized to do that.")
         |> push_navigate(to: ~p"/")}
    end
  end

  defp save(socket, :new, params) do
    Regions.create_region(socket.assigns.current_scope, params)
  end

  defp save(socket, :edit, params) do
    Regions.rename_region(socket.assigns.current_scope, socket.assigns.region, params)
  end

  defp saved_message(:new), do: "Region added."
  defp saved_message(:edit), do: "Region renamed."

  # The slug shown is the one the changeset would store: derived from the name
  # for a new region, fixed for an existing one.
  defp assign_form(socket, changeset) do
    socket
    |> assign(:form, to_form(changeset))
    |> assign(:slug, Ecto.Changeset.get_field(changeset, :slug))
  end
end
