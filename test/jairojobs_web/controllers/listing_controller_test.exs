defmodule JairojobsWeb.ListingControllerTest do
  @moduledoc """
  A listing's public page, `/jobs/<region>/<listing>` (spec 005). A plain page:
  every test here is one request, as a visitor's phone, a chat app or a search
  engine makes it. Listings reach each status through the real context
  functions.
  """
  use JairojobsWeb.ConnCase, async: true

  import Jairojobs.AccountsFixtures
  import Jairojobs.ListingsFixtures
  import Jairojobs.RegionsFixtures

  alias Jairojobs.Listings

  defp owner_url, do: &"https://jairojobs.test/my/listings/#{&1.id}"

  # A complete listing with `title` in `region`, approved: Published.
  defp published(scope, admin, title, region, attrs \\ %{}) do
    attrs = Map.merge(%{title: title, region_id: region.id}, Map.new(attrs))
    listing = listing_fixture(scope, complete_listing_attrs(attrs))
    {:ok, listing} = Listings.submit_listing(scope, listing, &admin_url/1)
    {:ok, listing, _email} = Listings.approve_listing(admin, listing, owner_url(), &public_url/1)
    flush_emails()
    listing
  end

  defp page(conn, path), do: conn |> get(path) |> html_response(200) |> LazyHTML.from_fragment()

  # The text of the elements that match, with runs of white space made one space.
  defp text(doc, selector) do
    doc |> LazyHTML.query(selector) |> LazyHTML.text() |> String.split() |> Enum.join(" ")
  end

  defp has?(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count() > 0

  setup do
    %{
      # An Admin owner has no limit on open listings (REQ-003-12).
      owner:
        admin_poster_scope_fixture(
          business_name: "Kape Isla",
          business_about: "Family-run café in Matina since 2019."
        ),
      admin: admin_scope_fixture(),
      davao: region_fixture(name: "Davao City"),
      cebu: region_fixture(name: "Cebu")
    }
  end

  describe "the listing's public page (REQ-005-5)" do
    setup %{owner: owner, admin: admin, davao: davao} do
      listing =
        published(owner, admin, "Barista (full-time)", davao,
          area: "Matina",
          salary_min: 14_000,
          salary_max: 16_000,
          employment_type: :full_time,
          schedule: "Shifting, 6 days",
          description:
            "We're a neighbourhood café.\nTraining is provided; espresso experience is a plus.",
          requirements: "At least 18 years old\nWilling to work weekends",
          benefits: "Free meals on shift"
        )

      %{listing: listing, path: "/jobs/davao-city/barista-full-time"}
    end

    test "REQ-005-5: Read a listing without an account", %{conn: conn, path: path} do
      doc = page(conn, path)

      assert text(doc, "#listing-title") == "Barista (full-time)"
      assert text(doc, "#listing-business") == "Kape Isla"

      assert text(doc, "#listing-salary") == "₱14,000–16,000 / month"
      assert text(doc, "#listing-location") == "Matina, Davao City"
      assert text(doc, "#listing-type") == "Full-time"
      assert text(doc, "#listing-schedule") == "Shifting, 6 days"

      body = text(doc, "#listing-detail")

      for heading <- ["About the job", "Requirements", "Benefits", "About Kape Isla"] do
        assert body =~ heading
      end

      assert body =~ "Training is provided; espresso experience is a plus."
      assert body =~ "Willing to work weekends"
      assert body =~ "Free meals on shift"
      assert body =~ "Family-run café in Matina since 2019."
    end

    test "the title is the page's one main heading, and the sections sit under it",
         %{conn: conn, path: path} do
      doc = page(conn, path)

      assert text(doc, "h1") == "Barista (full-time)"
      assert has?(doc, "h1#listing-title")

      assert doc
             |> LazyHTML.query("#listing-detail h2")
             |> Enum.map(&String.trim(LazyHTML.text(&1))) ==
               ["About the job", "Requirements", "Benefits", "About Kape Isla"]
    end

    test "text keeps its line breaks and is never read as HTML",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      published(owner, admin, "Cashier (weekends)", davao,
        description:
          "First line of the job.\nSecond line, with <b>tags</b> & an <script>alert(1)</script> in it.",
        requirements: "<a href=\"https://example.com\">a link</a>"
      )

      html = conn |> get("/jobs/davao-city/cashier-weekends") |> html_response(200)

      refute html =~ "<b>tags</b>"
      refute html =~ "<script>alert(1)</script>"
      refute html =~ ~s(<a href="https://example.com">)
      assert html =~ "&lt;b&gt;tags&lt;/b&gt;"
      assert html =~ "First line of the job.\nSecond line"
      assert has?(LazyHTML.from_fragment(html), "#listing-detail p.whitespace-pre-line")
    end

    test "REQ-005-5: The trust line", %{conn: conn, listing: listing, path: path} do
      approved_ago(listing, 2, :hour)

      doc = page(conn, path)

      assert text(doc, "#listing-trust") == "✓ Approved · Posted 2 h ago · Davao City"
      assert text(doc, "#listing-approved") == "✓ Approved"
      assert text(doc, "#listing-posted") == "Posted 2 h ago"
      assert text(doc, "#listing-region") == "Davao City"
    end

    test "REQ-005-5: An older listing shows the date", %{conn: conn, listing: listing, path: path} do
      listing = approved_ago(listing, 10, :day)

      doc = page(conn, path)

      assert text(doc, "#listing-posted") ==
               "Posted " <> JairojobsWeb.Format.manila_date(listing.published_at)

      refute text(doc, "#listing-posted") =~ "ago"
    end

    test "REQ-005-5: Optional parts are left out",
         %{conn: conn, admin: admin, davao: davao} do
      owner = admin_poster_scope_fixture(business_name: "Tindahan ni Aling Nena")

      published(owner, admin, "Store attendant", davao,
        schedule: nil,
        requirements: nil,
        benefits: nil
      )

      doc = page(conn, "/jobs/davao-city/store-attendant")
      body = text(doc, "#listing-detail")

      refute has?(doc, "#listing-schedule")
      refute body =~ "Schedule"
      refute body =~ "Requirements"
      refute body =~ "Benefits"
      refute body =~ "About Tindahan ni Aling Nena"
      refute body =~ "Not set yet"
      refute body =~ "Not written yet"

      # What is always there still is.
      assert body =~ "About the job"
      assert text(doc, "#listing-business") == "Tindahan ni Aling Nena"

      assert doc
             |> LazyHTML.query("#listing-detail h2")
             |> Enum.map(&String.trim(LazyHTML.text(&1))) ==
               ["About the job"]
    end

    test "REQ-005-5: The public sees the listing as it is now",
         %{conn: conn, admin: admin, listing: listing, path: path} do
      {:ok, _edited, _email} =
        Listings.update_listing_as_admin(
          admin,
          listing,
          %{business_name: "Kape Isla Café", area: "Lanang"},
          owner_url()
        )

      doc = page(conn, path)

      assert text(doc, "#listing-business") == "Kape Isla Café"
      assert text(doc, "#listing-location") == "Lanang, Davao City"
      assert text(doc, "#listing-detail") =~ "About Kape Isla Café"
    end

    test "the business shown is the listing's own copy, not the account's details now",
         %{conn: conn, owner: owner, path: path} do
      {:ok, _user} =
        Jairojobs.Accounts.update_business_details(owner, %{
          business_name: "Renamed Since",
          business_about: "Changed after the listing was submitted."
        })

      doc = page(conn, path)

      assert text(doc, "#listing-business") == "Kape Isla"
      refute text(doc, "#listing-detail") =~ "Renamed Since"
      refute text(doc, "#listing-detail") =~ "Changed after"
    end

    test "REQ-005-5: What is never shown",
         %{conn: conn, owner: owner, admin: admin, listing: listing, path: path} do
      html = conn |> get(path) |> html_response(200)
      doc = LazyHTML.from_fragment(html)

      # Not the account that posted it, not who approved it.
      refute html =~ owner.user.email
      refute html =~ admin.user.email

      # No status label, in words or as a pill.
      refute has?(doc, "[id^='listing-status']")
      refute has?(doc, ".badge")
      refute text(doc, "main") =~ "Published"

      # And no id: not the listing's, the owner's or the Admin's.
      refute html =~ listing.id
      refute html =~ owner.user.id
      refute html =~ admin.user.id
    end

    test "REQ-005-5: Applying is not possible yet", %{conn: conn, path: path} do
      doc = page(conn, path)

      assert text(doc, "#apply-coming-soon") == "Applying through jairojobs is coming soon."

      # No button to apply, and no accent action at all until spec 007.
      refute text(doc, "main") =~ "Apply for this job"
      refute has?(doc, "main .btn-accent")
      refute has?(doc, "main form")
    end

    test "REQ-005-5: Back to the region's jobs", %{conn: conn, path: path} do
      doc = page(conn, path)

      assert text(doc, "#back-to-region") == "Jobs in Davao City"

      assert LazyHTML.attribute(LazyHTML.query(doc, "a#back-to-region"), "href") == [
               "/jobs/davao-city"
             ]

      # Always the listing's own region, whatever list the visitor came from.
      doc = conn |> put_req_header("referer", "http://localhost/?search=barista") |> page(path)

      assert LazyHTML.attribute(LazyHTML.query(doc, "a#back-to-region"), "href") == [
               "/jobs/davao-city"
             ]
    end

    test "the page's title names the job, the business and the region",
         %{conn: conn, path: path} do
      assert conn |> page(path) |> text("title") ==
               "Barista (full-time) — Kape Isla, Davao City | jairojobs"
    end
  end

  describe "share a listing (REQ-005-8)" do
    setup %{owner: owner, admin: admin, davao: davao} do
      published(owner, admin, "Barista (full-time)", davao,
        area: "Matina",
        salary_min: 14_000,
        salary_max: 16_000
      )

      %{
        path: "/jobs/davao-city/barista-full-time",
        address: JairojobsWeb.Endpoint.url() <> "/jobs/davao-city/barista-full-time"
      }
    end

    defp meta(doc, property),
      do: doc |> LazyHTML.query(~s(meta[property="#{property}"])) |> LazyHTML.attribute("content")

    test "REQ-005-8: The page offers Share", %{conn: conn, path: path, address: address} do
      doc = page(conn, path)

      assert text(doc, "button#share-listing") == "Share"

      # It carries what the share sheet is given: the listing's title and its full
      # public address.
      button = LazyHTML.query(doc, "#share-listing")
      assert LazyHTML.attribute(button, "data-share-title") == ["Barista (full-time)"]
      assert LazyHTML.attribute(button, "data-share-url") == [address]
      assert String.starts_with?(address, "http")

      # The script that opens the share sheet, or copies the address, is attached to it,
      # and the line that will say "Link copied" is announced to screen readers.
      assert [hook] = LazyHTML.attribute(button, "phx-hook")
      assert String.ends_with?(hook, ".Share")
      assert LazyHTML.attribute(LazyHTML.query(doc, "#share-status"), "aria-live") == ["polite"]
      assert text(doc, "#share-status") == ""
    end

    test "Share comes before the \"coming soon\" line, and is not an accent button",
         %{conn: conn, path: path} do
      doc = page(conn, path)

      ids =
        doc
        |> LazyHTML.query("#listing-detail, #share-listing, #apply-coming-soon")
        |> LazyHTML.attribute("id")

      assert ids == ["listing-detail", "share-listing", "apply-coming-soon"]
      refute has?(doc, "#share-listing.btn-accent")
      refute has?(doc, "main .btn-accent")
    end

    test "nothing is added to the address to track who shared it, and no network has a button",
         %{conn: conn, path: path, address: address} do
      html = conn |> get(path) |> html_response(200)
      doc = LazyHTML.from_fragment(html)

      [shared] = LazyHTML.attribute(LazyHTML.query(doc, "#share-listing"), "data-share-url")
      assert shared == address
      refute shared =~ "?"
      refute shared =~ "utm"

      for network <- ~w(facebook messenger whatsapp twitter viber telegram linkedin) do
        refute String.downcase(html) =~ network
      end

      # One button, and it is the only thing on the page that shares.
      assert doc |> LazyHTML.query("[data-share-url]") |> Enum.count() == 1
    end

    test "REQ-005-8: A shared link has a preview", %{conn: conn, path: path, address: address} do
      # A chat app reads the page as first delivered and builds its preview from these.
      doc = page(conn, path)

      assert meta(doc, "og:title") == ["Barista (full-time) — Kape Isla"]
      assert meta(doc, "og:description") == ["₱14,000–16,000 / month · Matina, Davao City"]
      assert meta(doc, "og:url") == [address]
      assert meta(doc, "og:site_name") == ["jairojobs"]
      assert meta(doc, "og:type") == ["website"]

      # Text only: the site has no images.
      assert meta(doc, "og:image") == []
      refute has?(doc, ~s(meta[name="twitter:image"]))
    end

    test "the preview is of the listing as it is now, and its text cannot break out of the tag",
         %{conn: conn, owner: owner, admin: admin, cebu: cebu} do
      listing = published(owner, admin, ~s(Cook "nights" <b>), cebu, area: ~s(Lahug "IT Park"))

      {:ok, _edited, _email} =
        Listings.update_listing_as_admin(
          admin,
          listing,
          %{business_name: ~s(Kape "Isla" & Sons), salary_min: 15_000, salary_max: 15_000},
          owner_url()
        )

      html = conn |> get("/jobs/cebu/#{listing.slug}") |> html_response(200)
      doc = LazyHTML.from_fragment(html)

      assert meta(doc, "og:title") == [~s(Cook "nights" <b> — Kape "Isla" & Sons)]
      assert meta(doc, "og:description") == [~s(₱15,000 / month · Lahug "IT Park", Cebu)]
      refute html =~ ~s(content="Cook "nights")
      refute html =~ "<b> —"
    end

    test "a page that is not a listing's has no listing preview", %{
      conn: conn,
      owner: owner,
      path: path
    } do
      {:ok, _closed} =
        Listings.close_listing(
          owner,
          elem(Listings.resolve_public_address("davao-city", "barista-full-time"), 1)
        )

      doc = conn |> get(path) |> html_response(410) |> LazyHTML.from_fragment()

      # Nothing of a listing that is no longer listed, in the preview either.
      assert meta(doc, "og:title") == []
      assert meta(doc, "og:description") == []
      refute has?(doc, "#share-listing")
    end
  end

  describe "who can open it (REQ-005-1, REQ-005-8)" do
    setup %{owner: owner, admin: admin, davao: davao} do
      %{listing: published(owner, admin, "Barista (full-time)", davao)}
    end

    test "REQ-005-1: A Published listing is public without an account", %{conn: conn} do
      conn = get(conn, "/jobs/davao-city/barista-full-time")

      assert html_response(conn, 200) =~ "Barista (full-time)"
      refute get_session(conn, :user_token)
    end

    test "REQ-005-8: A shared link opens without an account", %{conn: conn} do
      # As a friend's phone opens a link from a chat: one request, nothing else first.
      conn = get(conn, "/jobs/davao-city/barista-full-time")

      assert conn.status == 200
      assert redirected_to_log_in?(conn) == false

      assert conn |> html_response(200) |> LazyHTML.from_fragment() |> text("#listing-title") ==
               "Barista (full-time)"
    end

    test "the same page for a Candidate, an Employer and an Admin", %{conn: conn, admin: admin} do
      for user <- [user_fixture(role: "candidate"), user_fixture(role: "employer"), admin.user] do
        doc = conn |> log_in_user(user) |> page("/jobs/davao-city/barista-full-time")

        assert text(doc, "#listing-title") == "Barista (full-time)"
        assert text(doc, "#apply-coming-soon") == "Applying through jairojobs is coming soon."
      end
    end

    test "REQ-005-1: A hidden region does not hide a listing",
         %{conn: conn, admin: admin, davao: davao} do
      {:ok, _hidden} = Jairojobs.Regions.hide_region(admin, davao)

      doc = page(conn, "/jobs/davao-city/barista-full-time")

      assert text(doc, "#listing-title") == "Barista (full-time)"
      assert text(doc, "#listing-region") == "Davao City"
    end

    defp redirected_to_log_in?(conn), do: conn.status in [301, 302]
  end

  describe "the address and the title (REQ-005-6)" do
    test "REQ-005-6: A changed title keeps the address",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      listing = published(owner, admin, "Barista (full-time)", davao)

      {:ok, _edited, _email} =
        Listings.update_listing_as_admin(
          admin,
          listing,
          %{title: "Barista (full-time, weekends)"},
          owner_url()
        )

      # The same address, and the page shows the new title.
      doc = page(conn, "/jobs/davao-city/barista-full-time")
      assert text(doc, "#listing-title") == "Barista (full-time, weekends)"

      # No new address was made from the new title.
      assert conn |> get("/jobs/davao-city/barista-full-time-weekends") |> response(404)
    end
  end

  describe "a listing that is no longer listed (REQ-005-7)" do
    @reason "The salary on this listing was not the salary offered."

    setup %{owner: owner, admin: admin, davao: davao} do
      listing =
        published(owner, admin, "Barista (full-time)", davao,
          area: "Matina",
          salary_min: 14_000,
          salary_max: 16_000,
          description: "We're a neighbourhood café with espresso machines and regulars.",
          requirements: "Willing to work weekends",
          benefits: "Free meals on shift"
        )

      %{listing: listing, path: "/jobs/davao-city/barista-full-time"}
    end

    defp close(owner, listing) do
      {:ok, closed} = Listings.close_listing(owner, listing)
      closed
    end

    defp take_down(admin, listing) do
      {:ok, taken_down, _email} =
        Listings.take_down_listing(admin, listing, %{reason: @reason}, owner_url())

      flush_emails()
      taken_down
    end

    defp gone_page(conn, path),
      do: conn |> get(path) |> html_response(410) |> LazyHTML.from_fragment()

    test "REQ-005-7: A closed listing's address says so",
         %{conn: conn, owner: owner, listing: listing, path: path} do
      close(owner, listing)

      doc = gone_page(conn, path)

      assert text(doc, "#listing-gone") == "This job is no longer listed."

      # And a way on: the jobs in its region.
      assert text(doc, "#see-region-jobs") == "See jobs in Davao City"

      assert LazyHTML.attribute(LazyHTML.query(doc, "a#see-region-jobs"), "href") == [
               "/jobs/davao-city"
             ]
    end

    test "REQ-005-7: A taken down listing's address says the same",
         %{conn: conn, owner: owner, admin: admin, davao: davao, listing: listing, path: path} do
      take_down(admin, listing)
      closed = close(owner, published(owner, admin, "Cashier (weekends)", davao))

      html = conn |> get(path) |> html_response(410)

      assert text(LazyHTML.from_fragment(html), "#listing-gone") ==
               "This job is no longer listed."

      refute html =~ @reason
      refute html =~ "salary offered"
      refute html =~ "taken down"
      refute html =~ "Taken down"

      # Word for word what a closed listing's address says: the public cannot tell which.
      taken_down_main = html |> LazyHTML.from_fragment() |> text("main")
      closed_main = conn |> gone_page("/jobs/davao-city/#{closed.slug}") |> text("main")

      assert taken_down_main == closed_main
    end

    test "REQ-005-7: Nothing of the listing is shown",
         %{conn: conn, owner: owner, admin: admin, davao: davao, listing: listing, path: path} do
      close(owner, listing)
      take_down(admin, published(owner, admin, "Cashier (weekends)", davao))

      for {path, title} <- [{path, "Barista"}, {"/jobs/davao-city/cashier-weekends", "Cashier"}] do
        html = conn |> get(path) |> html_response(410)

        # Not its title (in the page or in the page's title), business, salary or text.
        refute html =~ title
        refute html =~ "Kape Isla"
        refute html =~ "14,000"
        refute html =~ "₱"
        refute html =~ "espresso"
        refute html =~ "weekends"
        refute html =~ "Free meals"
        refute html =~ "Family-run"
        refute html =~ "Matina"

        doc = LazyHTML.from_fragment(html)
        refute has?(doc, "#listing-detail")
        refute has?(doc, "#listing-title")
        assert text(doc, "title") == "This job is no longer listed | jairojobs"
        assert text(doc, "h1") == "This job is no longer listed."
      end
    end

    test "REQ-005-7: The page is answered as gone",
         %{conn: conn, owner: owner, admin: admin, davao: davao, listing: listing, path: path} do
      # While it is Published the address answers normally.
      assert conn |> get(path) |> response(200)

      close(owner, listing)
      take_down(admin, published(owner, admin, "Cashier (weekends)", davao))

      # Gone: it was here and has been removed. Not "not found", which says it never was.
      assert get(conn, path).status == 410
      assert get(conn, "/jobs/davao-city/cashier-weekends").status == 410
      assert get(conn, "/jobs/davao-city/never-a-job").status == 404

      # It stays gone, and stays the listing's own address for good.
      assert get(conn, path).status == 410
    end

    test "REQ-005-7: The owner and Admins see the same page",
         %{conn: conn, owner: owner, admin: admin, listing: listing, path: path} do
      take_down(admin, listing)

      as_visitor = conn |> gone_page(path) |> text("#listing-gone")

      for user <- [owner.user, admin.user] do
        conn = conn |> log_in_user(user) |> get(path)
        html = html_response(conn, 410)
        doc = LazyHTML.from_fragment(html)

        assert text(doc, "#listing-gone") == as_visitor
        refute html =~ "Barista"
        refute html =~ "Kape Isla"
        refute html =~ @reason
        refute has?(doc, "#listing-detail")
      end
    end

    test "REQ-005-7: An address that never was a listing",
         %{conn: conn, owner: owner, davao: davao, listing: listing} do
      listing_in_status_fixture(owner, :pending, title: "A pending one", region_id: davao.id)
      listing_in_status_fixture(owner, :rejected, title: "A rejected one", region_id: davao.id)
      listing_fixture(owner, complete_listing_attrs(title: "Only a draft", region_id: davao.id))

      for path <- [
            "/jobs/davao-city/no-such-job",
            # A listing that was never approved has no address at all.
            "/jobs/davao-city/a-pending-one",
            "/jobs/davao-city/a-rejected-one",
            "/jobs/davao-city/only-a-draft",
            # The right slug in the wrong region, and an unknown region.
            "/jobs/cebu/barista-full-time",
            "/jobs/atlantis/barista-full-time",
            "/jobs/atlantis/no-such-job",
            "/jobs/davao-city/Barista-Full-Time",
            "/jobs/davao-city/barista%20full%20time",
            "/jobs/davao-city/#{listing.id}/edit"
          ] do
        conn = get(conn, path)

        assert conn.status == 404, path
        assert response(conn, 404) == "Not Found"
      end
    end
  end

  describe "earlier addresses, and what is never an address (REQ-005-6)" do
    defp move(admin, listing, region) do
      {:ok, moved, _email} =
        Listings.update_listing_as_admin(admin, listing, %{region_id: region.id}, owner_url())

      flush_emails()
      moved
    end

    setup %{owner: owner, admin: admin, davao: davao} do
      %{listing: published(owner, admin, "Barista (full-time)", davao)}
    end

    test "REQ-005-6: The id is never a public address",
         %{conn: conn, owner: owner, admin: admin, listing: listing} do
      assert get(conn, "/jobs/davao-city/#{listing.id}").status == 404
      assert get(conn, "/jobs/#{listing.region_id}/#{listing.id}").status == 404
      # (A region's list is a LiveView, where "not found" is raised.)
      assert_error_sent :not_found, fn -> get(conn, "/jobs/#{listing.id}") end

      # Not for its owner or an Admin either: the id opens private pages only.
      for user <- [owner.user, admin.user] do
        assert conn |> log_in_user(user) |> get("/jobs/davao-city/#{listing.id}") |> response(404)
      end
    end

    test "REQ-005-6: Moving to another region forwards the old address",
         %{conn: conn, admin: admin, cebu: cebu, listing: listing} do
      move(admin, listing, cebu)

      # The listing's page is at its new address…
      assert conn |> page("/jobs/cebu/barista-full-time") |> text("#listing-title") ==
               "Barista (full-time)"

      # …and the old one forwards there, for good, so a search engine moves over too.
      conn = get(conn, "/jobs/davao-city/barista-full-time")

      assert redirected_to(conn, 301) == "/jobs/cebu/barista-full-time"
    end

    test "a forward drops whatever was added to the old address",
         %{conn: conn, admin: admin, cebu: cebu, listing: listing} do
      move(admin, listing, cebu)

      conn = get(conn, "/jobs/davao-city/barista-full-time?search=barista&utm_source=chat")

      assert redirected_to(conn, 301) == "/jobs/cebu/barista-full-time"
    end

    test "every earlier address forwards straight to the current one",
         %{conn: conn, owner: owner, admin: admin, cebu: cebu, listing: listing} do
      manila = region_fixture(name: "Metro Manila")
      published(owner, admin, "Barista (full-time)", manila)

      listing |> then(&move(admin, &1, cebu)) |> then(&move(admin, &1, manila))

      # One step each, to where the listing is now, with the number it got there.
      for old <- ["/jobs/davao-city/barista-full-time", "/jobs/cebu/barista-full-time"] do
        assert conn |> get(old) |> redirected_to(301) == "/jobs/metro-manila/barista-full-time-2"
      end

      assert get(conn, "/jobs/metro-manila/barista-full-time-2").status == 200
    end

    test "REQ-005-6: An earlier address is not given to another listing either",
         %{conn: conn, owner: owner, admin: admin, davao: davao, cebu: cebu, listing: listing} do
      move(admin, listing, cebu)

      newcomer = published(owner, admin, "Barista (full-time)", davao, area: "Toril")
      assert newcomer.slug == "barista-full-time-2"

      # The old address still forwards to the moved listing, not to the newcomer.
      assert conn |> get("/jobs/davao-city/barista-full-time") |> redirected_to(301) ==
               "/jobs/cebu/barista-full-time"

      assert conn |> page("/jobs/davao-city/barista-full-time-2") |> text("#listing-location") ==
               "Toril, Davao City"
    end

    test "a listing moved back answers at its first address again, and the other forwards",
         %{conn: conn, admin: admin, davao: davao, cebu: cebu, listing: listing} do
      listing |> then(&move(admin, &1, cebu)) |> then(&move(admin, &1, davao))

      assert get(conn, "/jobs/davao-city/barista-full-time").status == 200

      assert conn |> get("/jobs/cebu/barista-full-time") |> redirected_to(301) ==
               "/jobs/davao-city/barista-full-time"
    end

    test "the old address of a listing that was moved and then closed forwards to the page that says it is no longer listed",
         %{conn: conn, owner: owner, admin: admin, cebu: cebu, listing: listing} do
      moved = move(admin, listing, cebu)
      {:ok, _closed} = Listings.close_listing(owner, moved)

      conn = get(conn, "/jobs/davao-city/barista-full-time")
      assert redirected_to(conn, 301) == "/jobs/cebu/barista-full-time"

      doc =
        build_conn()
        |> get("/jobs/cebu/barista-full-time")
        |> html_response(410)
        |> LazyHTML.from_fragment()

      assert text(doc, "#listing-gone") == "This job is no longer listed."
      assert text(doc, "#see-region-jobs") == "See jobs in Cebu"
    end

    test "`/jobs` with nothing after it forwards to the home page (plan decision 15)",
         %{conn: conn} do
      assert conn |> get("/jobs") |> redirected_to(301) == "/"
      assert conn |> get("/jobs?search=barista") |> redirected_to(301) == "/"
    end
  end

  describe "links to the pages that manage a listing (REQ-005-10)" do
    setup %{admin: admin, davao: davao} do
      employer = employer_scope_fixture(business_name: "Kape Isla")
      listing = published(employer, admin, "Barista (full-time)", davao)

      %{employer: employer, listing: listing, path: "/jobs/davao-city/barista-full-time"}
    end

    defp href(doc, selector), do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute("href")

    test "REQ-005-10: An Admin gets to the Admin view from the public page",
         %{conn: conn, admin: admin, listing: listing, path: path} do
      doc = conn |> log_in_user(admin.user) |> page(path)

      assert text(doc, "#open-admin-view") == "Open the Admin view"
      assert href(doc, "#manage-links a#open-admin-view") == ["/admin/listings/#{listing.id}"]

      # Not the owner: no "This is your listing.", no link to My listings.
      refute has?(doc, "#your-listing-note")
      refute has?(doc, "#manage-listing")
    end

    test "REQ-005-10: The owner gets to their listing from the public page",
         %{conn: conn, employer: employer, listing: listing, path: path} do
      doc = conn |> log_in_user(employer.user) |> page(path)

      assert text(doc, "#your-listing-note") == "This is your listing."
      assert text(doc, "#manage-listing") == "Manage this listing"
      assert href(doc, "#manage-links a#manage-listing") == ["/my/listings/#{listing.id}"]

      refute has?(doc, "#open-admin-view")
    end

    test "REQ-005-10: Nobody else sees those links",
         %{conn: conn, listing: listing, path: path} do
      visitor = conn
      candidate = log_in_user(conn, user_fixture(role: "candidate"))
      another_employer = log_in_user(conn, employer_scope_fixture().user)

      for conn <- [visitor, candidate, another_employer] do
        html = conn |> get(path) |> html_response(200)
        doc = LazyHTML.from_fragment(html)

        refute has?(doc, "#manage-links")
        refute has?(doc, "#manage-listing")
        refute has?(doc, "#open-admin-view")
        refute has?(doc, "#your-listing-note")
        refute html =~ "/admin/listings"
        refute html =~ "/my/listings/#{listing.id}"
        refute html =~ listing.id
      end
    end

    test "an Admin who owns the listing sees both links",
         %{conn: conn, admin: admin, davao: davao} do
      owner = admin_poster_scope_fixture()
      own = published(owner, admin, "Line cook (nights)", davao)

      doc = conn |> log_in_user(owner.user) |> page("/jobs/davao-city/line-cook-nights")

      assert text(doc, "#your-listing-note") == "This is your listing."
      assert href(doc, "#manage-listing") == ["/my/listings/#{own.id}"]
      assert href(doc, "#open-admin-view") == ["/admin/listings/#{own.id}"]
    end

    test "an owner who can no longer open My listings is not shown the link",
         %{conn: conn, admin: admin, davao: davao} do
      # An Admin who posted, then demoted to Candidate (spec 004, hand-offs to spec 008).
      owner = admin_poster_scope_fixture()
      published(owner, admin, "Line cook (nights)", davao)

      {:ok, demoted} =
        Jairojobs.Accounts.demote_admin(Jairojobs.Accounts.Scope.system(), owner.user)

      assert demoted.role == :candidate

      doc = conn |> log_in_user(demoted) |> page("/jobs/davao-city/line-cook-nights")

      refute has?(doc, "#manage-links")
      refute has?(doc, "#your-listing-note")
    end

    test "the links come last on the page, after the \"coming soon\" line",
         %{conn: conn, employer: employer, path: path} do
      doc = conn |> log_in_user(employer.user) |> page(path)

      ids =
        doc
        |> LazyHTML.query("#back-to-region, #listing-detail, #apply-coming-soon, #manage-links")
        |> LazyHTML.attribute("id")

      assert ids == ["back-to-region", "listing-detail", "apply-coming-soon", "manage-links"]
    end

    test "REQ-005-10: The same links on a listing that is no longer listed",
         %{
           conn: conn,
           admin: admin,
           employer: employer,
           davao: davao,
           listing: listing,
           path: path
         } do
      {:ok, _closed} = Listings.close_listing(employer, listing)

      taken_down = published(employer, admin, "Cashier (weekends)", davao)

      {:ok, _taken_down, _email} =
        Listings.take_down_listing(
          admin,
          taken_down,
          %{reason: "Not suitable for the board as it is written."},
          owner_url()
        )

      for {path, listing} <- [{path, listing}, {"/jobs/davao-city/cashier-weekends", taken_down}] do
        # The owner: a link to it in My listings.
        doc =
          conn
          |> log_in_user(employer.user)
          |> get(path)
          |> html_response(410)
          |> LazyHTML.from_fragment()

        assert text(doc, "#listing-gone") == "This job is no longer listed."
        assert text(doc, "#manage-listing") == "Manage this listing"
        assert href(doc, "#manage-listing") == ["/my/listings/#{listing.id}"]
        refute has?(doc, "#open-admin-view")

        # An Admin: a link to its Admin view.
        doc =
          conn
          |> log_in_user(admin.user)
          |> get(path)
          |> html_response(410)
          |> LazyHTML.from_fragment()

        assert text(doc, "#open-admin-view") == "Open the Admin view"
        assert href(doc, "#open-admin-view") == ["/admin/listings/#{listing.id}"]
        refute has?(doc, "#manage-listing")

        # Everyone else: neither, and no id.
        for conn <- [conn, log_in_user(conn, user_fixture(role: "candidate"))] do
          html = conn |> get(path) |> html_response(410)

          refute has?(LazyHTML.from_fragment(html), "#manage-links")
          refute html =~ listing.id
        end
      end
    end

    test "the links lead to pages that check who is asking, as before",
         %{conn: conn, listing: listing} do
      # Showing or hiding a link is a convenience, not the guard (REQ-004-1, REQ-003-14).
      another_employer = log_in_user(conn, employer_scope_fixture().user)

      assert_error_sent :not_found, fn -> get(another_employer, "/my/listings/#{listing.id}") end
      assert another_employer |> get("/admin/listings/#{listing.id}") |> redirected_to() == "/"
      assert conn |> get("/admin/listings/#{listing.id}") |> redirected_to() == "/users/log-in"
    end
  end

  describe "the owner's and the Admin's views are as they were (spec 003, spec 004)" do
    import Phoenix.LiveViewTest

    test "the title is still a second-level heading there, and there is no trust line",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      listing = published(owner, admin, "Barista (full-time)", davao)

      for path <- ["/my/listings/#{listing.id}", "/admin/listings/#{listing.id}"] do
        {:ok, view, _html} = conn |> log_in_user(owner.user) |> live(path)

        assert has_element?(view, "h2#listing-title", "Barista (full-time)")
        assert has_element?(view, "#listing-detail h3", "About the job")
        refute has_element?(view, "#listing-trust")
        refute has_element?(view, "#apply-coming-soon")
      end
    end
  end
end
