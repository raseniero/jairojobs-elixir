defmodule JairojobsWeb.Admin.RegionLive.Index do
  @moduledoc """
  Admin list of every region, active and hidden, with Hide / Show
  (spec 002 — REQ-002-1, REQ-002-4). Layout per `wireframe-regions-admin`.
  """
  use JairojobsWeb, :live_view

  alias Jairojobs.Regions

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <nav aria-label="Breadcrumb" class="text-sm text-base-content/70">
        <.link navigate={~p"/admin"} id="breadcrumb-admin" class="text-primary hover:underline">
          Admin
        </.link>
        <span aria-hidden="true">▸</span>
        <span class="font-semibold text-base-content">Regions</span>
      </nav>

      <div class="flex items-center justify-between gap-3">
        <h1 class="text-[22px] font-bold">Regions</h1>
        <.button navigate={~p"/admin/regions/new"} id="add-region" variant="accent">
          <.icon name="hero-plus" class="size-5" /> Add region
        </.button>
      </div>

      <ul id="regions" phx-update="stream" class="divide-y divide-base-300 border-y border-base-300">
        <li id="no-regions" class="hidden py-3 text-base-content/70 only:block">
          No regions yet. Add the first one.
        </li>
        <li
          :for={{dom_id, region} <- @streams.regions}
          id={dom_id}
          class="flex min-h-11 items-center justify-between gap-3 py-3"
        >
          <div class="min-w-0">
            <p class="flex flex-wrap items-center gap-x-2">
              <span class={[
                "text-[17px] font-semibold break-words",
                !region.active && "text-base-content/60"
              ]}>
                {region.name}
              </span>
              <span
                :if={!region.active}
                id={"region-hidden-#{region.id}"}
                class="badge badge-ghost badge-sm rounded-full"
              >
                hidden
              </span>
            </p>
            <p class="truncate text-sm text-base-content/70">/jobs/{region.slug}</p>
          </div>

          <div class="flex shrink-0 gap-2">
            <.button
              navigate={~p"/admin/regions/#{region.id}/edit"}
              id={"edit-region-#{region.id}"}
              aria-label={"Edit #{region.name}"}
            >
              Edit
            </.button>
            <.button
              :if={region.active}
              id={"hide-region-#{region.id}"}
              phx-click="hide"
              phx-value-id={region.id}
              aria-label={"Hide #{region.name}"}
            >
              Hide
            </.button>
            <.button
              :if={!region.active}
              id={"show-region-#{region.id}"}
              phx-click="show"
              phx-value-id={region.id}
              aria-label={"Show #{region.name}"}
            >
              Show
            </.button>
          </div>
        </li>
      </ul>

      <p id="regions-hint" class="text-xs text-base-content/70">
        Hidden regions stay on existing listings but can't be chosen.
      </p>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Regions")
     |> stream(:regions, Regions.list_regions())}
  end

  @impl true
  def handle_event("hide", %{"id" => id}, socket) do
    set_active(socket, id, &Regions.hide_region/2)
  end

  def handle_event("show", %{"id" => id}, socket) do
    set_active(socket, id, &Regions.show_region/2)
  end

  defp set_active(socket, id, fun) do
    region = Regions.get_region!(id)

    case fun.(socket.assigns.current_scope, region) do
      {:ok, region} ->
        {:noreply, stream_insert(socket, :regions, region)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You are not authorized to do that.")}
    end
  end
end
