defmodule JairojobsWeb.ListingHTML do
  @moduledoc """
  The pages rendered by `JairojobsWeb.ListingController` (spec 005).
  """
  use JairojobsWeb, :html

  import JairojobsWeb.ListingComponents

  alias JairojobsWeb.Format
  alias JairojobsWeb.PublicAddress

  embed_templates "listing_html/*"

  @doc """
  The links from a public page to the pages that manage the listing
  (REQ-005-10): "Manage this listing" for its owner, "Open the Admin view" for
  an Admin. Renders nothing for anyone else.

  `note` adds "This is your listing." for the owner, on the listing's own
  page. The "no longer listed" page has the links without it.
  """
  attr :manage, :map, required: true, doc: "`%{owner_path: …, admin_path: …}`, either may be nil"
  attr :note, :boolean, default: false

  def manage_links(assigns) do
    ~H"""
    <section
      :if={@manage.owner_path || @manage.admin_path}
      id="manage-links"
      aria-label="Manage this listing"
      class="rounded-md border border-base-300 bg-base-200 px-3 py-1 text-sm"
    >
      <p :if={@note && @manage.owner_path} id="your-listing-note" class="pt-2 font-semibold">
        This is your listing.
      </p>
      <div class="flex flex-wrap gap-x-6">
        <.link
          :if={@manage.owner_path}
          href={@manage.owner_path}
          id="manage-listing"
          class="inline-flex min-h-11 items-center text-primary hover:underline"
        >
          Manage this listing
        </.link>
        <.link
          :if={@manage.admin_path}
          href={@manage.admin_path}
          id="open-admin-view"
          class="inline-flex min-h-11 items-center text-primary hover:underline"
        >
          Open the Admin view
        </.link>
      </div>
    </section>
    """
  end
end
