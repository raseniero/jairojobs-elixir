defmodule JairojobsWeb.Employer.BusinessLiveTest do
  use JairojobsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Jairojobs.AccountsFixtures
  import Jairojobs.ListingsFixtures

  alias Jairojobs.Accounts

  describe "access" do
    test "REQ-003-1: candidate is refused", %{conn: conn} do
      conn = log_in_user(conn, user_fixture(role: "candidate"))

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/my/business")
      assert flash["error"] == "You are not authorized to access this page."
    end

    test "REQ-003-1: visitor is redirected to log in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/my/business")
    end
  end

  describe "first time" do
    setup %{conn: conn} do
      user = user_fixture(role: "employer")
      %{conn: log_in_user(conn, user), user: user}
    end

    test "REQ-003-2: saving business details continues to the listing form", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/my/business")

      assert has_element?(view, "#business-form")

      assert {:error, {:live_redirect, %{to: "/my/listings/new"}}} =
               view
               |> form("#business-form",
                 business: %{business_name: " Kape Isla ", business_about: "Family-run café."}
               )
               |> render_submit()

      user = Accounts.get_user!(user.id)
      assert user.business_name == "Kape Isla"
      assert user.business_about == "Family-run café."
    end

    test "REQ-003-2: business name is required", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/my/business")

      assert view |> form("#business-form", business: %{business_name: " "}) |> render_change() =~
               "can&#39;t be blank"

      assert view |> form("#business-form", business: %{business_name: ""}) |> render_submit() =~
               "can&#39;t be blank"

      assert view
             |> form("#business-form", business: %{business_name: String.duplicate("a", 81)})
             |> render_submit() =~ "should be at most 80 character(s)"

      assert has_element?(view, "#business-form")
      refute Accounts.business_details?(Accounts.get_user!(user.id))
    end

    test "REQ-003-1: an admin can save business details too", %{conn: conn} do
      admin = admin_fixture()
      {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/my/business")

      assert {:error, {:live_redirect, %{to: "/my/listings/new"}}} =
               view
               |> form("#business-form", business: %{business_name: "jairojobs"})
               |> render_submit()

      assert Accounts.get_user!(admin.id).business_name == "jairojobs"
    end
  end

  describe "changing them later" do
    test "REQ-003-2: change business details", %{conn: conn} do
      scope = employer_scope_fixture(business_name: "Kape Isla")
      {:ok, view, _html} = conn |> log_in_user(scope.user) |> live(~p"/my/business")

      assert view |> element("#business-form input[name='business[business_name]']") |> render() =~
               "Kape Isla"

      assert {:error, {:live_redirect, %{to: "/my/listings"}}} =
               view
               |> form("#business-form", business: %{business_name: "Kape Isla Matina"})
               |> render_submit()

      assert Accounts.get_user!(scope.user.id).business_name == "Kape Isla Matina"
    end
  end

  describe "logging" do
    test "REQ-003: listing and business form values are filtered from logged parameters" do
      params = %{
        "listing" => %{"title" => "Barista", "description" => "About the job"},
        "business" => %{"business_name" => "Kape Isla"},
        "id" => "123"
      }

      assert Phoenix.Logger.filter_values(params) == %{
               "listing" => "[FILTERED]",
               "business" => "[FILTERED]",
               "id" => "123"
             }
    end
  end
end
