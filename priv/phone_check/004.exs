# Spec 004 — admin moderation: the pages to check at phone width, and the data
# they need. Run by `scripts/phone-check.sh 004`; see `support.exs`.
Code.require_file("support.exs", __DIR__)

alias Jairojobs.Listings
alias Jairojobs.Regions

PhoneCheck.run(System.argv(), fn ->
  admin = PhoneCheck.admin() |> PhoneCheck.business(%{business_name: "Lutong Bahay ni Jairo"})

  employer = fn name ->
    PhoneCheck.account("employer")
    |> PhoneCheck.business(%{
      business_name: name,
      business_about: "Family-run café in Matina since 2019. We roast our own beans."
    })
  end

  kape_isla = employer.("Kape Isla")
  # A long name, to see it wrap.
  tindahan = employer.("Tindahan ni Aling Nena Sari-Sari Store and Eatery")

  region = PhoneCheck.region(admin, "Davao")
  to_hide = PhoneCheck.region(admin, "Baguio")

  # The addresses only go into emails, which land in the dev mailbox.
  owner_url = &"http://localhost/my/listings/#{&1.id}"
  admin_url = &"http://localhost/admin/listings/#{&1.id}"

  pending = fn scope, title, region ->
    {:ok, draft} =
      Listings.create_listing(scope, %{
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

    {:ok, listing} = Listings.submit_listing(scope, draft, admin_url)
    listing
  end

  approved = fn listing ->
    {:ok, listing, _email} = Listings.approve_listing(admin, listing, owner_url)
    listing
  end

  waiting = pending.(kape_isla, "Barista (full-time, opening shift)", region)
  in_hidden_region = pending.(kape_isla, "Cashier (weekends)", to_hide)
  own = pending.(admin, "Line cook (nights)", region)
  live = approved.(pending.(tindahan, "Store attendant", region))

  {:ok, taken_down, _email} =
    Listings.take_down_listing(
      admin,
      approved.(pending.(tindahan, "Delivery rider", region)),
      %{
        reason:
          "The business asked us to remove it because the position was filled through a referral."
      },
      owner_url
    )

  {:ok, rejected, _email} =
    Listings.reject_listing(
      admin,
      pending.(tindahan, "Dishwasher", region),
      %{reason: "Salary looks like a typo — did you mean 14,000?"},
      owner_url
    )

  {:ok, _hidden} = Regions.hide_region(admin, to_hide)

  view = &"/admin/listings/#{&1.id}"

  %{
    sessions: [
      %{
        name: "admin",
        login: PhoneCheck.login(admin),
        pages: [
          %{name: "01-admin-area", path: "/admin"},
          %{name: "02-queue", path: "/admin/listings"},
          %{name: "03-live-list", path: "/admin/listings?status=live"},
          %{name: "04-empty-list", path: "/admin/listings?status=closed"},
          %{name: "05-view-waiting", path: view.(waiting) <> "?from=waiting"},
          %{name: "06-view-hidden-region", path: view.(in_hidden_region)},
          %{name: "07-view-own", path: view.(own)},
          %{name: "08-view-live", path: view.(live) <> "?from=live"},
          %{name: "09-view-taken-down", path: view.(taken_down)},
          %{name: "10-view-rejected", path: view.(rejected)},
          %{name: "11-reject-form", path: view.(waiting) <> "/reject"},
          %{
            name: "12-reject-form-error",
            path: view.(waiting) <> "/reject",
            steps: [
              ["fill", "textarea[name='decision[reason]']", "short"],
              ["click", "#decision-submit"]
            ]
          },
          %{name: "13-take-down-form", path: view.(live) <> "/take-down"},
          %{name: "14-edit-form", path: view.(waiting) <> "/edit"}
        ]
      },
      %{
        name: "employer",
        login: PhoneCheck.login(tindahan),
        pages: [%{name: "15-owner-taken-down", path: "/my/listings/#{taken_down.id}"}]
      }
    ]
  }
end)
