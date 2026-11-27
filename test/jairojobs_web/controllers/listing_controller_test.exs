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
    {:ok, listing, _email} = Listings.approve_listing(admin, listing, owner_url())
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
