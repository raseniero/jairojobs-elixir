defmodule JairojobsWeb.UserLive.SettingsTest do
  use JairojobsWeb.ConnCase, async: true

  alias Jairojobs.Accounts
  import Phoenix.LiveViewTest
  import Jairojobs.AccountsFixtures

  describe "Settings page" do
    test "REQ-001-6: settings page renders for a logged-in user", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      assert html =~ "Change Email"
      assert html =~ "Save Password"
    end

    test "REQ-001-1: settings redirects a visitor to log in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "REQ-001-6: settings requires sudo mode", %{conn: conn} do
      {:ok, conn} =
        conn
        |> log_in_user(user_fixture(),
          token_authenticated_at: DateTime.add(DateTime.utc_now(), -11, :minute)
        )
        |> live(~p"/users/settings")
        |> follow_redirect(conn, ~p"/users/log-in")

      assert conn.resp_body =~ "You must re-authenticate to access this page."
    end
  end

  describe "account type" do
    test "REQ-001-9: role shown in Settings as a read-only label", %{conn: conn} do
      for {role, label} <- [candidate: "Candidate", employer: "Employer"] do
        {:ok, lv, _html} =
          conn
          |> log_in_user(user_fixture(role: to_string(role)))
          |> live(~p"/users/settings")

        assert has_element?(lv, "#account_type", label)
        refute has_element?(lv, "input[name='user[role]']")
        refute has_element?(lv, "select[name='user[role]']")
      end
    end

    test "REQ-001-9: admin role is shown as Admin", %{conn: conn} do
      user = user_fixture()
      {:ok, user} = user |> Ecto.Changeset.change(role: :admin) |> Jairojobs.Repo.update()

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings")

      assert has_element?(lv, "#account_type", "Admin")
    end

    test "REQ-001-9: users cannot change their own role", %{conn: conn} do
      user = user_fixture(role: "candidate")
      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      # Submit a forged role param alongside each settings form.
      lv
      |> form("#email_form", %{"user" => %{"email" => unique_user_email()}})
      |> render_submit(%{"user" => %{"role" => "admin"}})

      lv
      |> form("#password_form", %{
        "user" => %{
          "password" => valid_user_password(),
          "password_confirmation" => valid_user_password()
        }
      })
      |> render_submit(%{"user" => %{"role" => "admin"}})

      assert Accounts.get_user!(user.id).role == :candidate
    end
  end

  describe "update email form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "REQ-001-6: request email change sends a link and keeps the current email", %{
      conn: conn,
      user: user
    } do
      new_email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => new_email}
        })
        |> render_submit()

      assert result =~ "A link to confirm your email"
      assert Accounts.get_user_by_email(user.email)
    end

    test "REQ-001-6: invalid new email shows a validation error (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#email_form")
        |> render_change(%{
          "action" => "update_email",
          "user" => %{"email" => "with spaces"}
        })

      assert result =~ "Change Email"
      assert result =~ "must have the @ sign and no spaces"
    end

    test "REQ-001-6: unchanged email shows a validation error (phx-submit)", %{
      conn: conn,
      user: user
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => user.email}
        })
        |> render_submit()

      assert result =~ "Change Email"
      assert result =~ "did not change"
    end
  end

  describe "update password form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "REQ-001-7: change password updates the password", %{conn: conn, user: user} do
      new_password = valid_user_password()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      form =
        form(lv, "#password_form", %{
          "user" => %{
            "email" => user.email,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      render_submit(form)

      new_password_conn = follow_trigger_action(form, conn)

      assert redirected_to(new_password_conn) == ~p"/users/settings"

      assert get_session(new_password_conn, :user_token) != get_session(conn, :user_token)

      assert Phoenix.Flash.get(new_password_conn.assigns.flash, :info) =~
               "Password updated successfully"

      assert Accounts.get_user_by_email_and_password(user.email, new_password)
    end

    test "REQ-001-7: invalid new password shows a validation error (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#password_form")
        |> render_change(%{
          "user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      assert result =~ "Save Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end

    test "REQ-001-7: invalid new password shows a validation error (phx-submit)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#password_form", %{
          "user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })
        |> render_submit()

      assert result =~ "Save Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end
  end

  describe "confirm email" do
    setup %{conn: conn} do
      user = user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{conn: log_in_user(conn, user), token: token, email: email, user: user}
    end

    test "REQ-001-6: confirm new email updates the account once", %{
      conn: conn,
      user: user,
      token: token,
      email: email
    } do
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")

      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"info" => message} = flash
      assert message == "Email changed successfully."
      refute Accounts.get_user_by_email(user.email)
      assert Accounts.get_user_by_email(email)

      # use confirm token again
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
    end

    test "REQ-001-6: invalid change-email link is rejected", %{conn: conn, user: user} do
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/oops")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
      assert Accounts.get_user_by_email(user.email)
    end

    test "REQ-001-1: confirm-email page redirects a visitor to log in", %{token: token} do
      conn = build_conn()
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")
      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => message} = flash
      assert message == "You must log in to access this page."
    end
  end
end
