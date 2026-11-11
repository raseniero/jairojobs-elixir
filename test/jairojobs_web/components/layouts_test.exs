defmodule JairojobsWeb.LayoutsTest do
  use JairojobsWeb.ConnCase, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Jairojobs.AccountsFixtures

  alias Jairojobs.Accounts.Scope
  alias JairojobsWeb.Layouts

  defp render_app(scope) do
    assigns = %{scope: scope}

    rendered_to_string(~H"""
    <Layouts.app flash={%{}} current_scope={@scope}>content</Layouts.app>
    """)
  end

  defp ids(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#nav-drawer-menu [id^='nav-']")
    |> LazyHTML.attribute("id")
  end

  defp placeholder_ids(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#nav-drawer-menu [data-placeholder]")
    |> LazyHTML.attribute("id")
  end

  test "REQ-001-12: visitor navigation" do
    html = render_app(nil)

    assert ids(html) == ["nav-browse", "nav-signup", "nav-login"]
    assert placeholder_ids(html) == []
    assert html =~ ~s(id="nav-header-login")
    refute html =~ ~s(id="nav-header-account")
  end

  test "REQ-001-12: candidate navigation" do
    html = render_app(Scope.for_user(user_fixture(role: "candidate")))

    assert ids(html) == [
             "nav-browse",
             "nav-applications",
             "nav-profile",
             "nav-settings",
             "nav-logout"
           ]

    assert placeholder_ids(html) == ["nav-applications", "nav-profile"]
    assert html =~ ~s(id="nav-header-account")
  end

  test "REQ-001-12: employer navigation" do
    html = render_app(Scope.for_user(user_fixture(role: "employer")))

    assert ids(html) == [
             "nav-browse",
             "nav-listings",
             "nav-post-job",
             "nav-settings",
             "nav-logout"
           ]

    assert placeholder_ids(html) == ["nav-listings", "nav-post-job"]
  end

  test "REQ-001-12: admin navigation" do
    html = render_app(Scope.for_user(admin_fixture()))

    assert ids(html) == ["nav-browse", "nav-admin", "nav-settings", "nav-logout"]
    assert placeholder_ids(html) == []
  end

  test "REQ-002-1: admin navigation links to the admin area" do
    html = render_app(Scope.for_user(admin_fixture()))

    assert html
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("#nav-drawer-menu #nav-admin")
           |> LazyHTML.attribute("href") == ["/admin"]
  end

  test "REQ-001-12: every drawer item is at least 44px tall and the menu button is labelled" do
    html = render_app(nil)
    doc = LazyHTML.from_fragment(html)

    assert LazyHTML.query(doc, "label[for='nav-drawer'][aria-label='Open menu']") |> Enum.any?()

    doc
    |> LazyHTML.query("#nav-drawer-menu [id^='nav-']")
    |> LazyHTML.attribute("class")
    |> Enum.each(fn class -> assert class =~ "min-h-11" end)
  end
end
