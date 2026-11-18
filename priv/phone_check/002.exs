# Spec 002 — regions: the pages to check at phone width, and the data they
# need. Run by `scripts/phone-check.sh 002`; see `support.exs`.
Code.require_file("support.exs", __DIR__)

alias Jairojobs.Regions

PhoneCheck.run(System.argv(), fn ->
  admin = PhoneCheck.admin()
  region = PhoneCheck.region(admin, "Iloilo City")
  # A long name, to see the row wrap beside its two buttons.
  PhoneCheck.region(admin, "San Fernando City La Union")
  {:ok, _hidden} = Regions.hide_region(admin, PhoneCheck.region(admin, "Baguio"))

  %{
    sessions: [
      %{
        name: "admin",
        login: PhoneCheck.login(admin),
        pages: [
          %{name: "01-admin-area", path: "/admin"},
          %{name: "02-regions", path: "/admin/regions"},
          %{name: "03-new-region", path: "/admin/regions/new"},
          %{
            name: "04-new-region-error",
            path: "/admin/regions/new",
            steps: [["click", "#region-form button"]]
          },
          %{name: "05-edit-region", path: "/admin/regions/#{region.id}/edit"}
        ]
      }
    ]
  }
end)
