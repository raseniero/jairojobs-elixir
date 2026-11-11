defmodule Jairojobs.AccountsTest do
  use Jairojobs.DataCase

  alias Jairojobs.Accounts

  import Jairojobs.AccountsFixtures
  alias Jairojobs.Accounts.{Scope, User, UserToken}

  describe "get_user_by_email/1" do
    test "REQ-001-4: unregistered email returns no user" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "REQ-001-4: registered email returns the user" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "REQ-001-5: unknown email returns no user" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "REQ-001-5: wrong password returns no user" do
      user = user_fixture() |> set_password()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "REQ-001-5: valid email and password return the user" do
      %{id: id} = user = user_fixture() |> set_password()

      assert %User{id: ^id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end

    test "REQ-001-5: unconfirmed user cannot log in with a password" do
      user = unconfirmed_user_fixture() |> set_password()
      refute user.confirmed_at
      refute Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end

  describe "get_user!/1" do
    test "REQ-001-9: get_user! raises for an unknown id" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!("11111111-1111-1111-1111-111111111111")
      end
    end

    test "REQ-001-9: get_user! returns the user by id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "register_user/1" do
    test "REQ-001-2: email is required" do
      {:error, changeset} = Accounts.register_user(%{})

      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "REQ-001-2: invalid email format is rejected" do
      {:error, changeset} = Accounts.register_user(%{email: "not valid"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "REQ-001-2: over-long email is rejected" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.register_user(%{email: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "REQ-001-2: existing email does not create a duplicate account" do
      %{email: email} = user_fixture()
      {:error, changeset} = Accounts.register_user(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the uppercased email too, to check that email case is ignored.
      {:error, changeset} = Accounts.register_user(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "REQ-001-2: successful sign-up creates an account without a password" do
      email = unique_user_email()
      {:ok, user} = Accounts.register_user(valid_user_attributes(email: email))
      assert user.email == email
      assert is_nil(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
    end

    test "REQ-001-2: successful sign-up persists the chosen role" do
      {:ok, user} = Accounts.register_user(valid_user_attributes(role: "employer"))
      assert user.role == :employer
      assert Accounts.get_user!(user.id).role == :employer
      assert is_nil(user.previous_role)
    end

    test "REQ-001-2: missing role is rejected" do
      {:error, changeset} = Accounts.register_user(%{email: unique_user_email()})
      assert %{role: ["can't be blank"]} = errors_on(changeset)
    end

    test "REQ-001-2: forged admin role is rejected" do
      {:error, changeset} = Accounts.register_user(valid_user_attributes(role: "admin"))
      assert %{role: ["is invalid"]} = errors_on(changeset)

      {:error, changeset} = Accounts.register_user(valid_user_attributes(role: "superuser"))
      assert %{role: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "sudo_mode?/2" do
    test "REQ-001-6: sudo mode expires 10 minutes after authentication" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Accounts.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Accounts.sudo_mode?(%User{})
    end
  end

  describe "change_user_email/3" do
    test "REQ-001-6: returns an email changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "deliver_user_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "REQ-001-6: request email change sends a change-email token", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = unconfirmed_user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "REQ-001-6: confirm new email updates the account email", %{
      user: user,
      token: token,
      email: email
    } do
      assert {:ok, %{email: ^email}} = Accounts.update_user_email(user, token)
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "REQ-001-6: invalid change-email token is rejected", %{user: user} do
      assert Accounts.update_user_email(user, "oops") ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "REQ-001-6: change-email token is bound to the issuing address", %{
      user: user,
      token: token
    } do
      assert Accounts.update_user_email(%{user | email: "current@example.com"}, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "REQ-001-6: expired change-email token is rejected", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Accounts.update_user_email(user, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "change_user_password/3" do
    test "REQ-001-5: returns a password changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})
      assert changeset.required == [:password]
    end

    test "REQ-001-5: password changeset hashes the password" do
      changeset =
        Accounts.change_user_password(
          %User{},
          %{
            "password" => "new valid password"
          },
          hash_password: false
        )

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "REQ-001-5: password shorter than 12 characters is rejected", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "REQ-001-5: password over 72 bytes is rejected", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_user_password(user, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "REQ-001-5: set a password, then log in with it", %{user: user} do
      {:ok, {user, expired_tokens}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      assert expired_tokens == []
      assert is_nil(user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "REQ-001-7: change password logs out other sessions", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, {_, _}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "REQ-001-9: session token is stored for the user", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.authenticated_at != nil

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end

    test "REQ-001-9: session token keeps authenticated_at", %{user: user} do
      user = %{user | authenticated_at: DateTime.add(DateTime.utc_now(), -3600)}
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.authenticated_at == user.authenticated_at
      assert DateTime.compare(user_token.inserted_at, user.authenticated_at) == :gt
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "REQ-001-9: session token resolves to the user", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "REQ-001-9: invalid session token resolves to no user" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "REQ-001-9: expired session token resolves to no user", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "get_user_by_magic_link_token/1" do
    setup do
      user = user_fixture()
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      %{user: user, token: encoded_token}
    end

    test "REQ-001-4: magic link token resolves to the user", %{user: user, token: token} do
      assert session_user = Accounts.get_user_by_magic_link_token(token)
      assert session_user.id == user.id
    end

    test "REQ-001-4: invalid magic link token resolves to no user" do
      refute Accounts.get_user_by_magic_link_token("oops")
    end

    test "REQ-001-4: expired magic link token resolves to no user", %{token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_magic_link_token(token)
    end
  end

  describe "login_user_by_magic_link/1" do
    test "REQ-001-3: first link confirms the account and expires other tokens" do
      user = unconfirmed_user_fixture()
      refute user.confirmed_at
      {encoded_token, hashed_token} = generate_user_magic_link_token(user)

      assert {:ok, {user, [%{token: ^hashed_token}]}} =
               Accounts.login_user_by_magic_link(encoded_token)

      assert user.confirmed_at
    end

    test "REQ-001-4: magic link logs in a confirmed user and is single-use" do
      user = user_fixture()
      assert user.confirmed_at
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      assert {:ok, {^user, []}} = Accounts.login_user_by_magic_link(encoded_token)
      # one time use only
      assert {:error, :not_found} = Accounts.login_user_by_magic_link(encoded_token)
    end

    test "REQ-001-3: unconfirmed user with a password cannot use a magic link" do
      user = unconfirmed_user_fixture()
      {1, nil} = Repo.update_all(User, set: [hashed_password: "hashed"])
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)

      assert_raise RuntimeError, ~r/magic link log in is not allowed/, fn ->
        Accounts.login_user_by_magic_link(encoded_token)
      end
    end
  end

  describe "delete_user_session_token/1" do
    test "REQ-001-8: log out deletes the session token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "deliver_login_instructions/2" do
    setup do
      %{user: unconfirmed_user_fixture()}
    end

    test "REQ-001-4: request a magic link sends a login token", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "login"
    end
  end

  ## spec 001 — admin promotion / demotion (REQ-001-10, REQ-001-11)

  describe "promote_to_admin/2" do
    test "REQ-001-11: admin promotes a user and the previous role is remembered" do
      admin_scope = admin_scope_fixture()

      for role <- [:candidate, :employer] do
        user = user_fixture(role: to_string(role))
        assert {:ok, promoted} = Accounts.promote_to_admin(admin_scope, user)
        assert promoted.role == :admin
        assert promoted.previous_role == role

        reloaded = Accounts.get_user!(user.id)
        assert reloaded.role == :admin
        assert reloaded.previous_role == role
      end
    end

    test "REQ-001-11: the system scope may promote" do
      user = user_fixture()
      assert {:ok, %User{role: :admin}} = Accounts.promote_to_admin(Scope.system(), user)
    end

    test "REQ-001-11: promoting an admin is a no-op" do
      admin = admin_fixture(role: "employer")
      assert {:ok, same} = Accounts.promote_to_admin(Scope.system(), admin)
      assert same.role == :admin
      assert same.previous_role == :employer
    end

    test "REQ-001-11: non-admin cannot promote" do
      target = user_fixture()

      for scope <- [
            user_scope_fixture(user_fixture(role: "candidate")),
            user_scope_fixture(user_fixture(role: "employer")),
            nil
          ] do
        assert {:error, :unauthorized} = Accounts.promote_to_admin(scope, target)
      end

      assert Accounts.get_user!(target.id).role == :candidate
    end

    test "REQ-001-10: unconfirmed user cannot be promoted" do
      user = unconfirmed_user_fixture()
      assert {:error, :unconfirmed} = Accounts.promote_to_admin(Scope.system(), user)
      assert Accounts.get_user!(user.id).role == :candidate
    end
  end

  describe "demote_admin/2" do
    test "REQ-001-11: admin demotes another admin back to the remembered role" do
      admin_scope = admin_scope_fixture()
      target = admin_fixture(role: "employer")

      assert {:ok, demoted} = Accounts.demote_admin(admin_scope, target)
      assert demoted.role == :employer
      assert is_nil(demoted.previous_role)
      assert Accounts.get_user!(target.id).role == :employer
    end

    test "REQ-001-11: demote falls back to candidate if the previous role is unknown" do
      _other_admin = admin_fixture()
      target = admin_fixture()
      {:ok, target} = target |> Ecto.Changeset.change(previous_role: nil) |> Repo.update()

      assert {:ok, %User{role: :candidate}} = Accounts.demote_admin(Scope.system(), target)
    end

    test "REQ-001-11: last admin is protected" do
      only_admin = admin_fixture()
      assert Accounts.count_admins() == 1

      assert {:error, :last_admin} = Accounts.demote_admin(Scope.system(), only_admin)
      assert {:error, :last_admin} = Accounts.demote_admin(Scope.for_user(only_admin), only_admin)
      assert Accounts.get_user!(only_admin.id).role == :admin
    end

    test "REQ-001-11: non-admin cannot demote" do
      _other_admin = admin_fixture()
      target = admin_fixture()

      for scope <- [user_scope_fixture(user_fixture()), nil] do
        assert {:error, :unauthorized} = Accounts.demote_admin(scope, target)
      end

      assert Accounts.get_user!(target.id).role == :admin
    end

    test "REQ-001-11: demoting a non-admin is refused" do
      user = user_fixture()
      assert {:error, :not_admin} = Accounts.demote_admin(Scope.system(), user)
    end
  end

  describe "count_admins/0" do
    test "REQ-001-11: counts only admins" do
      assert Accounts.count_admins() == 0
      _candidate = user_fixture()
      admin_fixture()
      admin_fixture()
      assert Accounts.count_admins() == 2
    end
  end

  describe "inspect/2 for the User module" do
    test "NFR privacy: inspect does not include the password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end

  describe "business details (spec 003)" do
    setup do
      %{scope: Scope.for_user(user_fixture(role: "employer"))}
    end

    test "REQ-003-2: an employer saves business details", %{scope: scope} do
      refute Accounts.business_details?(scope.user)

      assert {:ok, user} =
               Accounts.update_business_details(scope, %{
                 business_name: "  Kape Isla  ",
                 business_about: "Family-run café since 2019."
               })

      assert user.business_name == "Kape Isla"
      assert user.business_about == "Family-run café since 2019."
      assert Accounts.business_details?(user)
      assert Accounts.get_user!(user.id).business_name == "Kape Isla"
    end

    test "REQ-003-2: an admin saves business details" do
      assert {:ok, user} =
               Accounts.update_business_details(admin_scope_fixture(), %{
                 business_name: "jairojobs"
               })

      assert user.business_name == "jairojobs"
    end

    test "REQ-003-2: business name is required", %{scope: scope} do
      for name <- ["", "   ", nil] do
        assert {:error, changeset} =
                 Accounts.update_business_details(scope, %{business_name: name})

        assert "can't be blank" in errors_on(changeset).business_name
      end

      assert {:error, changeset} = Accounts.update_business_details(scope, %{business_name: "K"})
      assert "should be at least 2 character(s)" in errors_on(changeset).business_name

      assert {:error, changeset} =
               Accounts.update_business_details(scope, %{
                 business_name: String.duplicate("a", 81)
               })

      assert "should be at most 80 character(s)" in errors_on(changeset).business_name

      refute Accounts.business_details?(Accounts.get_user!(scope.user.id))
    end

    test "REQ-003-2: about the business is optional and at most 500 characters", %{scope: scope} do
      assert {:error, changeset} =
               Accounts.update_business_details(scope, %{
                 business_name: "Kape Isla",
                 business_about: String.duplicate("a", 501)
               })

      assert "should be at most 500 character(s)" in errors_on(changeset).business_about

      assert {:ok, user} =
               Accounts.update_business_details(scope, %{
                 business_name: "Kape Isla",
                 business_about: String.duplicate("a", 500)
               })

      assert {:ok, user} =
               Accounts.update_business_details(Scope.for_user(user), %{
                 business_name: "Kape Isla",
                 business_about: ""
               })

      assert user.business_about == nil
    end

    test "REQ-003-2: a candidate cannot save business details" do
      candidate = user_fixture(role: "candidate")

      for scope <- [Scope.for_user(candidate), nil, Scope.system()] do
        assert {:error, :unauthorized} =
                 Accounts.update_business_details(scope, %{business_name: "Kape Isla"})
      end

      refute Accounts.business_details?(Accounts.get_user!(candidate.id))
    end

    test "REQ-003-2: other account fields cannot be changed through business details", %{
      scope: scope
    } do
      assert {:ok, user} =
               Accounts.update_business_details(scope, %{
                 business_name: "Kape Isla",
                 role: "admin",
                 email: "other@example.com"
               })

      assert user.role == :employer
      assert user.email == scope.user.email
    end

    test "REQ-003-2: change_business_details/2 returns a changeset for the form", %{scope: scope} do
      assert %Ecto.Changeset{} =
               changeset = Accounts.change_business_details(scope.user, %{business_name: "K"})

      refute changeset.valid?
    end

    test "REQ-003-2: the database refuses a business name outside 2–80 characters", %{
      scope: scope
    } do
      assert_raise Ecto.ConstraintError, ~r/users_business_name_length/, fn ->
        scope.user |> Ecto.Changeset.change(business_name: "K") |> Repo.update()
      end
    end
  end
end
