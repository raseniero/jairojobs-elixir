# Spec 003 — employer posting: the pages to check at phone width, and the data
# they need. Run by `scripts/phone-check.sh 003`; see `support.exs`.
Code.require_file("support.exs", __DIR__)

alias Jairojobs.Listings

PhoneCheck.run(System.argv(), fn ->
  admin = PhoneCheck.admin()
  region = PhoneCheck.region(admin, "Davao")

  employer =
    PhoneCheck.account("employer")
    |> PhoneCheck.business(%{
      business_name: "Kape Isla",
      business_about: "Family-run café in Matina since 2019. We roast our own beans."
    })

  newcomer = PhoneCheck.account("employer")

  # The addresses only go into emails, which land in the dev mailbox.
  owner_url = &"http://localhost/my/listings/#{&1.id}"
  admin_url = &"http://localhost/admin/listings/#{&1.id}"

  draft = fn title ->
    {:ok, listing} =
      Listings.create_listing(employer, %{
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
        benefits: "Free meals on shift"
      })

    listing
  end

  pending = fn title ->
    {:ok, listing} = Listings.submit_listing(employer, draft.(title), admin_url)
    listing
  end

  approved = fn title ->
    {:ok, listing, _email} = Listings.approve_listing(admin, pending.(title), owner_url)
    listing
  end

  {:ok, unfinished} = Listings.create_listing(employer, %{title: "Dishwasher"})
  complete_draft = draft.("Server (weekends, with a rather long title to wrap)")

  {:ok, rejected, _email} =
    Listings.reject_listing(
      admin,
      pending.("Line cook (nights)"),
      %{reason: "Salary looks like a typo — did you mean 14,000?"},
      owner_url
    )

  {:ok, closed} = Listings.close_listing(employer, approved.("Cashier"))
  live = approved.("Barista (full-time)")
  waiting = pending.("Store attendant")

  view = &"/my/listings/#{&1.id}"

  %{
    sessions: [
      %{
        name: "employer",
        login: PhoneCheck.login(employer),
        pages: [
          %{name: "01-my-listings", path: "/my/listings"},
          %{name: "02-business-details", path: "/my/business"},
          %{name: "03-new-listing", path: "/my/listings/new"},
          %{
            name: "04-new-listing-error",
            path: "/my/listings/new",
            steps: [
              ["fill", "#listing_salary_min", "16000"],
              ["fill", "#listing_salary_max", "14000"],
              ["click", "#listing-form button"]
            ]
          },
          %{name: "05-draft-unfinished", path: view.(unfinished)},
          %{name: "06-draft-complete", path: view.(complete_draft)},
          %{name: "07-waiting", path: view.(waiting)},
          %{name: "08-needs-changes", path: view.(rejected)},
          %{name: "09-published", path: view.(live)},
          %{name: "10-closed", path: view.(closed)},
          %{name: "11-edit-listing", path: view.(rejected) <> "/edit"}
        ]
      },
      %{
        name: "newcomer",
        login: PhoneCheck.login(newcomer),
        pages: [
          %{name: "12-no-listings-yet", path: "/my/listings"},
          %{name: "13-business-details-first", path: "/my/business"}
        ]
      }
    ]
  }
end)
