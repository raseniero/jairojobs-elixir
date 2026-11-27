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
  "Share": sends a listing's public page to someone else (REQ-005-8).

  The button carries the listing's title and its full public address. A small
  script, attached as a hook, does the rest when it is tapped:

    1. where the browser has a share sheet (most phones), it opens it with the
       title and the address; a sheet that is closed again does nothing;
    2. otherwise it copies the address and says "Link copied";
    3. where it can do neither (an old browser, or a page not served over
       HTTPS), it writes the address out so it can be copied by hand.

  There are no buttons for particular apps, and nothing is added to the
  address to track who shared it. This is hand-written JavaScript because the
  share sheet and the clipboard exist only in the browser (constitution §2.3).
  LiveView runs hooks on a page that has no LiveView too, and opens no
  connection for it.

  The test suite has no browser, so it checks what the button carries; what a
  tap does is checked by hand (see `tasks.md`).
  """
  attr :listing, :map, required: true

  def share(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
      <%!-- A plain button, not the accent: this page has no accent action until spec 007. --%>
      <button
        type="button"
        id="share-listing"
        phx-hook=".Share"
        data-share-title={@listing.title}
        data-share-url={PublicAddress.listing_url(@listing)}
        class="btn min-h-11 border border-base-300 btn-ghost"
      >
        <.icon name="hero-share" class="size-5" /> Share
      </button>
      <p id="share-status" aria-live="polite" class="min-w-0 text-sm break-all text-base-content/70">
      </p>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Share">
      export default {
        mounted() {
          this.el.addEventListener("click", async () => {
            const title = this.el.dataset.shareTitle
            const url = this.el.dataset.shareUrl
            const status = document.getElementById("share-status")

            if (navigator.share) {
              try {
                await navigator.share({title, url})
                return
              } catch (error) {
                // The visitor closed the share sheet: nothing to do or to say.
                if (error.name === "AbortError") return
                // Anything else: fall through and copy the address instead.
              }
            }

            try {
              await navigator.clipboard.writeText(url)
              status.textContent = "Link copied"
            } catch (_error) {
              // Neither is possible here: show the address so it can be copied by hand.
              status.textContent = url
            }
          })
        }
      }
    </script>
    """
  end

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
