defmodule JairojobsWeb.UserLive.Registration do
  use JairojobsWeb, :live_view

  alias Jairojobs.Accounts
  alias Jairojobs.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>
            Register for an account
            <:subtitle>
              Already registered?
              <.link navigate={~p"/users/log-in"} class="font-semibold text-brand hover:underline">
                Log in
              </.link>
              to your account now.
            </:subtitle>
          </.header>
        </div>

        <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />

          <.button phx-disable-with="Creating account..." class="btn btn-primary w-full">
            Create an account
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: JairojobsWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_email(%User{}, %{}, validate_unique: false)

    {:ok, assign_form(socket, changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        {:noreply, check_your_email(socket, user.email)}

      {:error, %Ecto.Changeset{} = changeset} ->
        # REQ-001-2: an existing email must not be revealed. If the only problem is that the
        # address is already registered, respond exactly like a successful sign-up — but
        # create nothing and send nothing.
        if email_taken_only?(changeset) do
          {:noreply, check_your_email(socket, Ecto.Changeset.get_field(changeset, :email))}
        else
          {:noreply, assign_form(socket, changeset)}
        end
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_email(%User{}, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp check_your_email(socket, email) do
    socket
    |> put_flash(
      :info,
      "An email was sent to #{email}, please access it to confirm your account."
    )
    |> push_navigate(to: ~p"/users/log-in")
  end

  defp email_taken_only?(%Ecto.Changeset{errors: [email: {_msg, opts}]}) do
    opts[:constraint] == :unique or opts[:validation] == :unsafe_unique
  end

  defp email_taken_only?(_changeset), do: false

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
