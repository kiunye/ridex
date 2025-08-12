defmodule RidexWeb.UserChannel do
  @moduledoc """
  Channel for user-specific notifications and presence tracking
  """
  use RidexWeb, :channel

  alias Ridex.Presence

  @impl true
  def join("user:" <> user_id, _payload, socket) do
    # Verify the user can only join their own channel
    if authorized?(socket, user_id) do
      # Track user presence
      send(self(), {:after_join, user_id})
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def join("users:lobby", _payload, socket) do
    # Anyone can join the lobby to see online users
    send(self(), :after_join_lobby)
    {:ok, socket}
  end

  @impl true
  def handle_info({:after_join, user_id}, socket) do
    # Track user presence when they join their personal channel
    case Presence.track_user(socket, user_id) do
      {:ok, _} ->
        # Broadcast that user came online
        Presence.broadcast_presence_update(user_id, "user_online")
        push(socket, "presence_state", Presence.list(socket))

      {:error, reason} ->
        push(socket, "presence_error", %{reason: reason})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:after_join_lobby, socket) do
    # Send current presence state to new lobby member
    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  # Handle custom presence updates
  @impl true
  def handle_info({:presence_update, update}, socket) do
    push(socket, "presence_update", update)
    {:noreply, socket}
  end

  # Handle user notifications
  @impl true
  def handle_info({:user_notification, notification}, socket) do
    push(socket, "notification", notification)
    {:noreply, socket}
  end

  # Handle trip notifications
  @impl true
  def handle_info({:trip_notification, trip_id, event, data}, socket) do
    push(socket, "trip_notification", %{
      trip_id: trip_id,
      event: event,
      data: data,
      timestamp: System.system_time(:second)
    })
    {:noreply, socket}
  end

  # Handle presence diff updates
  @impl true
  def handle_info(%{event: "presence_diff", payload: diff}, socket) do
    push(socket, "presence_diff", diff)
    {:noreply, socket}
  end

  @impl true
  def handle_in("status_update", %{"status" => status}, socket) do
    user_id = socket.assigns.current_user.id

    case Presence.update_user_status(socket, user_id, status) do
      {:ok, _} ->
        Presence.broadcast_presence_update(user_id, "status_changed", %{status: status})
        {:reply, {:ok, %{status: status}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @impl true
  def handle_in("get_online_users", _payload, socket) do
    online_users = Presence.get_online_users() |> Enum.to_list()
    {:reply, {:ok, %{users: online_users}}, socket}
  end

  @impl true
  def handle_in("get_online_drivers", _payload, socket) do
    online_drivers = Presence.get_online_drivers()
    {:reply, {:ok, %{drivers: online_drivers}}, socket}
  end

  @impl true
  def handle_in("ping", _payload, socket) do
    # Keep connection alive and update last seen
    user_id = socket.assigns.current_user.id
    Presence.update_user_presence(socket, user_id, %{last_ping: System.system_time(:second)})
    {:reply, {:ok, %{pong: true}}, socket}
  end



  # Intercept presence events to broadcast them
  intercept ["presence_diff"]

  @impl true
  def handle_out("presence_diff", diff, socket) do
    push(socket, "presence_diff", diff)
    {:noreply, socket}
  end

  # Authorization helper
  defp authorized?(socket, user_id) do
    current_user = socket.assigns.current_user
    current_user && current_user.id == user_id
  end
end
