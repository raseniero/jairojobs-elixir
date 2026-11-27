# Spec 005 — public browse and search: the pages to check at phone width, and the
# data they need. Run by `scripts/phone-check.sh 005`; see `support.exs`.
Code.require_file("support.exs", __DIR__)

alias Jairojobs.Listings
alias Jairojobs.Regions

PhoneCheck.run(System.argv(), fn ->
  # An Admin owner has no limit on open listings, so one account can fill a list.
  admin = PhoneCheck.admin() |> PhoneCheck.business(%{business_name: "Lutong Bahay ni Jairo"})

  employer = fn name ->
    PhoneCheck.account("employer")
    |> PhoneCheck.business(%{
      business_name: name,
      business_about: "Family-run café in Matina since 2019. We roast our own beans."
    })
  end

  kape_isla = employer.("Kape Isla")
  # A long name, to see it wrap on a row and on the listing's page.
  tindahan = employer.("Tindahan ni Aling Nena Sari-Sari Store and Eatery")

  region = PhoneCheck.region(admin, "Davao")
  empty = PhoneCheck.region(admin, "Cebu")
  to_hide = PhoneCheck.region(admin, "Baguio")

  # The addresses only go into emails, which land in the dev mailbox.
  owner_url = &"http://localhost/my/listings/#{&1.id}"
  admin_url = &"http://localhost/admin/listings/#{&1.id}"
  public_url = &"http://localhost/jobs/#{&1.region.slug}/#{&1.slug}"

  publish = fn scope, title, region, attrs ->
    {:ok, draft} =
      Listings.create_listing(
        scope,
        Map.merge(
          %{
            title: title,
            region_id: region.id,
            area: "Matina",
            salary_min: 14_000,
            salary_max: 16_000,
            employment_type: :full_time,
            schedule: "Shifting, 6 days",
            description:
              "We're a neighbourhood café looking for a barista who enjoys talking to " <>
                "regulars. You will open the shop three mornings a week.",
            requirements: "At least 18 years old\nCan work weekends",
            benefits: "Free meals on shift\nSSS, PhilHealth, Pag-IBIG"
          },
          attrs
        )
      )

    {:ok, pending} = Listings.submit_listing(scope, draft, admin_url)
    {:ok, listing, _email} = Listings.approve_listing(admin, pending, owner_url, public_url)
    listing
  end

  # More than 20, so the list has "Show more".
  for n <- 1..21 do
    publish.(admin, "Line cook, shift #{n}", region, %{employment_type: :part_time})
  end

  barista = publish.(kape_isla, "Barista (full-time)", region, %{})

  long =
    publish.(
      tindahan,
      "Customer Service Representative for the Night Shift at the Lanang Branch (with allowance)",
      region,
      %{
        area: "Lanang, near the old public market and the jeepney terminal",
        schedule: "Night shift, Monday to Saturday, with one weekend a month"
      }
    )

  # Only what is required: no schedule, requirements, benefits or "about".
  bare_owner =
    PhoneCheck.account("employer") |> PhoneCheck.business(%{business_name: "JR Printing"})

  bare =
    publish.(bare_owner, "Press operator", region, %{
      schedule: nil,
      requirements: nil,
      benefits: nil
    })

  own = publish.(admin, "Kitchen helper", region, %{})

  {:ok, closed} =
    Listings.close_listing(kape_isla, publish.(kape_isla, "Cashier (weekends)", region, %{}))

  hidden = publish.(admin, "Front desk clerk", to_hide, %{})
  {:ok, _hidden} = Regions.hide_region(admin, to_hide)

  list = &"/jobs/#{&1.slug}"
  page = &"/jobs/#{&1.region.slug}/#{&1.slug}"

  %{
    sessions: [
      %{
        name: "visitor",
        pages: [
          %{name: "01-home", path: "/"},
          %{name: "02-home-shown-40", path: "/?shown=40"},
          %{name: "03-region", path: list.(region)},
          %{name: "04-region-empty", path: list.(empty)},
          %{name: "05-hidden-region", path: list.(to_hide)},
          %{name: "06-search", path: list.(region) <> "?search=barista&type=full-time"},
          %{name: "07-search-nothing", path: "/?search=astronaut"},
          %{
            name: "08-search-typed",
            path: "/",
            steps: [["fill", "#search-words", "kape isla"], ["click", "#search-submit"]]
          },
          %{name: "09-listing", path: page.(barista)},
          %{name: "10-listing-long", path: page.(long)},
          %{name: "11-listing-bare", path: page.(bare)},
          %{name: "12-listing-hidden-region", path: page.(hidden)},
          # No share sheet in this browser; whatever "Share" then says is on the page.
          %{name: "13-listing-shared", path: page.(long), steps: [["click", "#share-listing"]]},
          %{name: "14-no-longer-listed", path: "/jobs/#{region.slug}/#{closed.slug}"}
        ]
      },
      %{
        name: "owner",
        login: PhoneCheck.login(kape_isla),
        pages: [
          %{name: "15-listing-as-owner", path: page.(barista)},
          %{name: "16-no-longer-listed-as-owner", path: "/jobs/#{region.slug}/#{closed.slug}"},
          %{name: "17-owner-view-published", path: "/my/listings/#{barista.id}"}
        ]
      },
      %{
        name: "admin",
        login: PhoneCheck.login(admin),
        pages: [
          %{name: "18-listing-as-admin", path: page.(barista)},
          %{name: "19-own-listing-as-admin", path: page.(own)},
          %{name: "20-no-longer-listed-as-admin", path: "/jobs/#{region.slug}/#{closed.slug}"},
          %{name: "21-admin-view-published", path: "/admin/listings/#{barista.id}"}
        ]
      }
    ]
  }
end)
