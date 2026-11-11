defmodule JairojobsWeb.Employer.BusinessLive do
  @moduledoc """
  The business an Employer (or Admin) posts listings for (spec 003,
  REQ-003-2). Asked once before the first listing; changeable later.
  """
  use JairojobsWeb, :live_view

  alias Jairojobs.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-1">
        <h1 class="text-[22px] font-bold">Business details</h1>
        <p class="text-sm text-base-content/70">
          {if @first_time?,
            do: "Before your first job post, tell us who is hiring.",
            else: "Changes apply to listings you submit from now on."}
        </p>
      </div>

      <.form
        for={@form}
        id="business-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
        <.input
          field={@form[:business_name]}
          type="text"
          label="Business name"
          maxlength="80"
          autocomplete="organization"
          phx-mounted={JS.focus()}
        />
        <.input
          field={@form[:business_about]}
          type="textarea"
          label="About the business (optional)"
          maxlength="500"
          rows="3"
        />
        <p class="text-xs text-base-content/70">Shown on every listing you post.</p>

        <div class="flex items-center gap-4">
          <.button variant="accent" phx-disable-with="Saving…">
            {if @first_time?, do: "Save and continue", else: "Save"}
          </.button>
          <.link
            :if={!@first_time?}
            navigate={~p"/my/listings"}
            id="business-form-cancel"
            class="inline-flex min-h-11 items-center text-primary hover:underline"
          >
            Cancel
          </.link>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:page_title, "Business details")
     |> assign(:first_time?, not Accounts.business_details?(user))
     |> assign_form(Accounts.change_business_details(user))}
  end

  @impl true
  def handle_event("validate", %{"business" => params}, socket) do
    changeset = Accounts.change_business_details(socket.assigns.current_scope.user, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"business" => params}, socket) do
    case Accounts.update_business_details(socket.assigns.current_scope, params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Business details saved.")
         |> push_navigate(to: next_path(socket.assigns.first_time?))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, "You are not authorized to do that.")
         |> push_navigate(to: ~p"/")}
    end
  end

  # First time: carry on to the listing the user came to post. Later: back to the list.
  defp next_path(true), do: ~p"/my/listings/new"
  defp next_path(false), do: ~p"/my/listings"

  # Params travel under "business" (not "user") so they can be filtered from logs.
  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: :business))
  end
end
