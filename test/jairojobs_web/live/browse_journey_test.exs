defmodule JairojobsWeb.BrowseJourneyTest do
  @moduledoc """
  One listing, from an Employer's post to "This job is no longer listed.", as
  the public meets it (spec 005, plan → Test strategy): approved, found on the
  home page, by region and by search, opened, moved to another region, and
  closed. It goes through the real screens of all three people and follows
  every link, forward and redirect the way a browser would.

  A `Phoenix.LiveViewTest` and controller journey, not a browser test
  (constitution §3.1): JavaScript and CSS are outside it.
  """
  # Not async (constitution §3.5): region names and slugs are unique, and these tests use
  # fixed region names ("Davao City", "Cebu") because the public addresses they check are
  # made from the region's slug. Concurrent sandbox transactions inserting the same names
  # wait on each other's unique-index entries and can deadlock.
  use JairojobsWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Jairojobs.AccountsFixtures
  import Jairojobs.ListingsFixtures
  import Jairojobs.RegionsFixtures

  defp text(html, selector) when is_binary(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.text()
    |> String.split()
    |> Enum.join(" ")
  end

  defp text(view, selector), do: view |> render() |> text(selector)

  defp row_titles(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#job-rows > a h2")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  defp href(html, selector),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> LazyHTML.attribute("href")

  # The emails sent since the last call, as `{recipient, subject, body}`.
  defp emails(acc \\ []) do
    receive do
      {:email, %Swoosh.Email{to: [{_name, address}]} = email} ->
        emails([{address, email.subject, email.text_body} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "a listing is posted, approved, found, opened, moved and closed", %{conn: visitor} do
    davao = region_fixture(name: "Davao City")
    cebu = region_fixture(name: "Cebu")
    employer = employer_scope_fixture(business_name: "Kape Isla")
    admin = admin_fixture()
    employer_conn = log_in_user(build_conn(), employer.user)
    admin_conn = log_in_user(build_conn(), admin)

    # Something else is already listed, in the other region.
    other = admin_poster_scope_fixture(business_name: "Tindahan ni Aling Nena")

    listing_in_status_fixture(other, :published,
      title: "Store attendant",
      region_id: cebu.id,
      description: "A steady job with a friendly team in a busy neighbourhood shop."
    )

    # 1. The Employer posts a listing and submits it. Nothing of it is public yet.
    {:ok, form, _html} = live(employer_conn, ~p"/my/listings/new")

    {:ok, owner_view, _html} =
      form
      |> form("#listing-form",
        listing:
          complete_listing_attrs(
            title: "Barista (full-time)",
            region_id: davao.id,
            area: "Matina",
            salary_min: 14_000,
            salary_max: 16_000
          )
          |> Map.update!(:employment_type, &Atom.to_string/1)
      )
      |> render_submit()
      |> follow_redirect(employer_conn)

    owner_view |> element("#submit-listing") |> render_click()
    refute has_element?(owner_view, "#see-public-page")

    {:ok, home, _html} = live(visitor, ~p"/")
    assert row_titles(home) == ["Store attendant"]
    assert visitor |> get("/jobs/davao-city/barista-full-time") |> response(404)
    _setup = emails()

    # 2. An Admin approves it from the queue. The Employer is emailed its public address.
    {:ok, queue, _html} = live(admin_conn, ~p"/admin/listings")

    {:ok, review, _html} =
      queue
      |> element("#admin-listings a", "Barista (full-time)")
      |> render_click()
      |> follow_redirect(admin_conn)

    review |> element("#approve-listing") |> render_click()

    assert [{to, "Your listing is published: Barista (full-time)", body}] =
             Enum.filter(emails(), &(elem(&1, 0) == employer.user.email))

    assert to == employer.user.email
    public_address = JairojobsWeb.Endpoint.url() <> "/jobs/davao-city/barista-full-time"
    assert body =~ public_address

    # 3. A visitor opens the site: the newest job is first, with what a row shows.
    {:ok, home, _html} = live(visitor, ~p"/")

    assert row_titles(home) == ["Barista (full-time)", "Store attendant"]
    assert text(home, "#jobs-count") == "2 jobs · newest first"

    row = text(home, "#job-davao-city--barista-full-time")
    assert row =~ "Kape Isla · Matina, Davao City"
    assert row =~ "₱14,000–16,000/mo"
    assert row =~ "✓ Approved"

    # 4. They choose their city, then search, then narrow by type; the address follows.
    home |> element("#region-choice-davao-city") |> render_click()
    assert_patch(home, "/jobs/davao-city")
    assert row_titles(home) == ["Barista (full-time)"]
    assert text(home, "#jobs-count") == "1 job in Davao City · newest first"

    home |> form("#search-form", %{search: "kape matina"}) |> render_submit()
    assert_patch(home, "/jobs/davao-city?search=kape+matina")
    assert row_titles(home) == ["Barista (full-time)"]

    home
    |> form("#search-form", %{search: "kape matina", type: "part-time"})
    |> render_change(%{"_target" => ["type"]})

    assert text(home, "#no-jobs") == "No jobs match your search."

    home |> element("#clear-search") |> render_click()
    assert_patch(home, "/jobs/davao-city")

    # 5. They tap the row and read the listing, with no account.
    assert {:error, {:redirect, %{to: "/jobs/davao-city/barista-full-time" = path}}} =
             home |> element("#job-davao-city--barista-full-time") |> render_click()

    page = visitor |> get(path) |> html_response(200)

    assert text(page, "#listing-title") == "Barista (full-time)"
    assert text(page, "#listing-business") == "Kape Isla"
    assert text(page, "#listing-salary") == "₱14,000–16,000 / month"
    assert text(page, "#listing-trust") =~ "✓ Approved · Posted just now · Davao City"
    assert text(page, "#apply-coming-soon") == "Applying through jairojobs is coming soon."
    assert text(page, "#share-listing") == "Share"
    assert href(page, "#back-to-region") == ["/jobs/davao-city"]
    assert text(page, "#manage-links") == ""

    # The address in the email is this page; the Employer sees their link on it.
    assert String.ends_with?(public_address, path)
    as_owner = employer_conn |> get(path) |> html_response(200)
    assert text(as_owner, "#your-listing-note") == "This is your listing."

    {:ok, owner_view, _html} = live(employer_conn, hd(href(as_owner, "#manage-listing")))
    assert href(render(owner_view), "#see-public-page") == [path]

    # 6. The Admin, on the public page, opens the Admin view and moves it to Cebu.
    as_admin = admin_conn |> get(path) |> html_response(200)
    {:ok, review, _html} = live(admin_conn, hd(href(as_admin, "#open-admin-view")))

    {:ok, edit, _html} =
      review |> element("#admin-edit-listing") |> render_click() |> follow_redirect(admin_conn)

    {:ok, review, _html} =
      edit
      |> form("#listing-form", listing: %{region_id: cebu.id})
      |> render_submit()
      |> follow_redirect(admin_conn)

    assert href(render(review), "#see-public-page") == ["/jobs/cebu/barista-full-time"]

    # 7. The link the visitor kept forwards to the listing's new address, and it is on
    #    Cebu's list now, not Davao's.
    moved = get(visitor, path)
    assert redirected_to(moved, 301) == "/jobs/cebu/barista-full-time"

    page = visitor |> get(redirected_to(moved, 301)) |> html_response(200)
    assert text(page, "#listing-location") == "Matina, Cebu"
    assert href(page, "#back-to-region") == ["/jobs/cebu"]

    {:ok, davao_list, _html} = live(visitor, ~p"/jobs/davao-city")
    assert text(davao_list, "#no-jobs") == "No jobs are listed in Davao City yet."

    {:ok, cebu_list, _html} = live(visitor, ~p"/jobs/cebu")
    assert row_titles(cebu_list) == ["Barista (full-time)", "Store attendant"]

    # 8. The job is filled: the Employer closes it. It leaves every list and the sitemap.
    {:ok, owner_view, _html} = live(employer_conn, hd(href(as_owner, "#manage-listing")))
    owner_view |> element("#close-listing") |> render_click()
    refute has_element?(owner_view, "#see-public-page")

    {:ok, home, _html} = live(visitor, ~p"/")
    assert row_titles(home) == ["Store attendant"]
    {:ok, searched, _html} = live(visitor, "/?search=barista")
    assert text(searched, "#no-jobs") == "No jobs match your search."

    sitemap = visitor |> get("/sitemap.xml") |> response(200)
    refute sitemap =~ "barista-full-time"
    assert sitemap =~ "/jobs/cebu/store-attendant"

    # 9. Its address says so, and nothing more; the old one still forwards to it.
    gone = get(visitor, "/jobs/cebu/barista-full-time")
    html = html_response(gone, 410)

    assert text(html, "#listing-gone") == "This job is no longer listed."
    assert href(html, "#see-region-jobs") == ["/jobs/cebu"]
    refute html =~ "Barista"
    refute html =~ "Kape Isla"

    assert visitor |> get(path) |> redirected_to(301) == "/jobs/cebu/barista-full-time"

    # The Employer still gets to their listing from there, and reads it in My listings.
    as_owner = employer_conn |> get("/jobs/cebu/barista-full-time") |> html_response(410)
    {:ok, owner_view, _html} = live(employer_conn, hd(href(as_owner, "#manage-listing")))
    assert text(owner_view, "span[id^=listing-status-]") == "Closed"
    assert text(owner_view, "#listing-title") == "Barista (full-time)"

    # 10. A new "Barista (full-time)" in Cebu, or in Davao, never takes either address.
    for region <- [cebu, davao] do
      again =
        listing_in_status_fixture(other, :published,
          title: "Barista (full-time)",
          region_id: region.id
        )

      assert again.slug == "barista-full-time-2"
    end
  end
end
