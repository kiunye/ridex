defmodule RidexWeb.UserRegistrationLive do
  use RidexWeb, :live_view

  alias Ridex.Accounts

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        Register for Ridex
        <:subtitle>
          Already registered?
          <.link navigate={~p"/users/log_in"} class="font-semibold text-brand hover:underline">
            Sign in
          </.link>
          to your account now.
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="registration_form"
        phx-submit="save"
        phx-change="validate"
        phx-trigger-action={@trigger_submit}
        action={~p"/users/log_in?_action=registered"}
        method="post"
      >
        <.error :if={@check_errors}>
          Oops, something went wrong! Please check the errors below.
        </.error>

        <.input field={@form[:email]} type="email" label="Email" required />
        <.input field={@form[:name]} type="text" label="Full Name" required />
        <.input field={@form[:phone]} type="tel" label="Phone Number" />
        <.input field={@form[:password]} type="password" label="Password" required />
        <.input
          field={@form[:password_confirmation]}
          type="password"
          label="Confirm Password"
          required
        />

        <div class="space-y-2">
            <label class="block text-sm font-semibold leading-6 text-zinc-800">
              I want to join as
            </label>
            <div class="flex gap-4">
              <label class="flex items-center gap-2 cursor-pointer">
                <input type="radio"
                      name="user[role]"
                      value="rider"
                      checked={@role == "rider"}
                      class="w-4 h-4 text-brand border-gray-300 focus:ring-brand"
                      phx-change="select_role" />
                <span class="text-sm font-medium">Rider</span>
                <span class="text-xs text-gray-500">(Request rides)</span>
              </label>
              <label class="flex items-center gap-2 cursor-pointer">
                <input type="radio"
                      name="user[role]"
                      value="driver"
                      checked={@role == "driver"}
                      class="w-4 h-4 text-brand border-gray-300 focus:ring-brand"
                      phx-change="select_role" />
                <span class="text-sm font-medium">Driver</span>
                <span class="text-xs text-gray-500">(Provide rides)</span>
              </label>
            </div>
          </div>

        <:actions>
          <.button phx-disable-with="Creating account..." class="w-full">
            Create an account
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%{"role" => "rider"})

    socket =
      socket
      |> assign(trigger_submit: false, check_errors: false, role: "rider")
      |> assign_form(changeset)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    # Use role from form params if provided, otherwise use socket assigns
    role = Map.get(user_params, "role", socket.assigns.role)
    user_params_with_role = Map.put(user_params, "role", role)

    case Accounts.create_user_with_profile(user_params_with_role) do
      {:ok, _user} ->
        changeset = Accounts.change_user_registration(%{})
        {:noreply, socket |> assign(trigger_submit: true) |> assign_form(changeset)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  # def handle_event("select_role", %{"role" => role}, socket) do
  #   # Get current form params or start with empty map
  #   current_params = if socket.assigns.form && socket.assigns.form.params do
  #     socket.assigns.form.params
  #   else
  #     %{}
  #   end

  #   # Update the role in the params
  #   updated_params = Map.put(current_params, "role", role)

  #   # Create new changeset with updated role
  #   changeset = Accounts.change_user_registration(updated_params)
  #   {:noreply, assign_form(socket, changeset)}
  # end
  def handle_event("select_role", %{"user" => %{"role" => role}}, socket) do
    {:noreply, assign(socket, role: role)}
  end

  def handle_event("select_role", %{"role" => role}, socket) do
    {:noreply, assign(socket, role: role)}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end
end
