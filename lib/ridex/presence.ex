defmodule Ridex.Presence do
  @moduledoc """
  Provides presence tracking to channels and processes.

  See the [`Phoenix.Presence`](https://hexdocs.pm/phoenix/Phoenix.Presence.html)
  docs for more details.
  """
  use Phoenix.Presence,
    otp_app: :ridex,
    pubsub_server: Ridex.PubSub

  alias Ridex.Accounts

  @doc """
  Track a user's presence when they come online
  """
  def track_user(socket, user_id, meta \\ %{}) do
    user = Accounts.get_user!(user_id)

    default_meta = %{
      user_id: user_id,
      name: user.name,
      role: user.role,
      status: "online",
      joined_at: System.system_time(:second)
    }

    merged_meta = Map.merge(default_meta, meta)

    track(socket.channel_pid, "users:lobby", user_id, merged_meta)
  end

  @doc """
  Update a user's presence metadata
  """
  def update_user_presence(socket, user_id, meta) do
    update(socket.channel_pid, "users:lobby", user_id, meta)
  end

  @doc """
  Get all online users
  """
  def get_online_users do
    list("users:lobby")
  end

  @doc """
  Get all online drivers
  """
  def get_online_drivers do
    "users:lobby"
    |> list()
    |> Enum.filter(fn {_user_id, %{metas: metas}} ->
      Enum.any?(metas, fn meta -> meta.role == :driver end)
    end)
  end

  @doc """
  Get all online riders
  """
  def get_online_riders do
    "users:lobby"
    |> list()
    |> Enum.filter(fn {_user_id, %{metas: metas}} ->
      Enum.any?(metas, fn meta -> meta.role == :rider end)
    end)
  end

  @doc """
  Check if a user is online
  """
  def user_online?(user_id) do
    case get_by_key("users:lobby", user_id) do
      [] -> false
      _presence -> true
    end
  end

  @doc """
  Get a specific user's presence
  """
  def get_user_presence(user_id) do
    case get_by_key("users:lobby", user_id) do
      [] -> nil
      presence -> presence
    end
  end

  @doc """
  Update user status (online, away, busy, offline)
  """
  def update_user_status(socket, user_id, status) do
    case get_user_presence(user_id) do
      nil ->
        {:error, :user_not_present}
      _presence ->
        update_user_presence(socket, user_id, %{status: status, updated_at: System.system_time(:second)})
    end
  end

  @doc """
  Broadcast presence updates to all subscribers
  """
  def broadcast_presence_update(user_id, event, meta \\ %{}) do
    Phoenix.PubSub.broadcast(
      Ridex.PubSub,
      "presence:updates",
      {:presence_update, %{user_id: user_id, event: event, meta: meta}}
    )
  end
end
