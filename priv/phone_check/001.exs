# Spec 001 — accounts and navigation: the pages to check at phone width, and
# the data they need. Run by `scripts/phone-check.sh 001`; see `support.exs`.
Code.require_file("support.exs", __DIR__)

PhoneCheck.run(System.argv(), fn ->
  open_menu = [["click", "label[aria-label='Open menu']"]]

  # A log-in link nobody uses: the confirmation page a visitor lands on from the email.
  unused_link = PhoneCheck.login(PhoneCheck.account("candidate"))

  signed_in = fn name, scope, extra ->
    %{
      name: name,
      login: PhoneCheck.login(scope),
      pages: [%{name: "menu", path: "/", steps: open_menu} | extra]
    }
  end

  %{
    sessions: [
      %{
        name: "visitor",
        pages: [
          %{name: "01-home", path: "/"},
          %{name: "02-menu", path: "/", steps: open_menu},
          %{name: "03-sign-up", path: "/users/register"},
          %{
            name: "04-sign-up-error",
            path: "/users/register",
            steps: [
              ["fill", "#registration_form input[type='email']", "not-an-email"],
              ["click", "#registration_form button"]
            ]
          },
          %{name: "05-log-in", path: "/users/log-in"},
          %{name: "06-log-in-link", path: unused_link}
        ]
      },
      signed_in.("candidate", PhoneCheck.account("candidate"), [
        %{name: "settings", path: "/users/settings"}
      ]),
      signed_in.("employer", PhoneCheck.account("employer"), []),
      signed_in.("admin", PhoneCheck.admin(), [])
    ]
  }
end)
