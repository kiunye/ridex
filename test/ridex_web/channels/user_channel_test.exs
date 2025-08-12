defmodule RidexWeb.UserChannelTest do
  use RidexWeb.ChannelCase

  alias Ridex.Presence
  alias Ridex.Accounts

  import Ridex.AccountsFixtures

  setup do
    user = user_fixture()
    {:ok, socket} = connect(RidexWeb.UserSocket, %{"token" => Accounts.generate_user_socket_token(user)})
    {:ok, user: user, socket: socket}
  end

  describe "joining user channel" do
    test "user can join their own channel", %{socket: socket, user: user} do
      {:ok, _, socket} = subscribe_and_join(socket, "user:#{user.id}", %{})

      assert socket.assigns.current_user.id == user.id
    end

    test "user cannot join another user's channel", %{socket: socket} do
      other_user = user_fixture()

      assert {:error, %{reason: "unauthorized"}} =
        subscribe_and_join(socket, "user:#{other_user.id}", %{})
    end

    test "anyone can join the lobby", %{socket: socket} do
      {:ok, _, _socket} = subscribe_and_join(socket, "users:lobby", %{})
    end

    test "joining user channel tracks presence", %{socket: socket, user: user} do
      refute Presence.user_online?(user.id)

      {:ok, _, _socket} = subscribe_and_join(socket, "user:#{user.id}", %{})

      # Give presence tracking time to complete
      :timer.sleep(100)

      assert Presence.user_online?(user.id)
    end
  end

  describe "status updates" do
    setup %{socket: socket, user: user} do
      {:ok, _, socket} = subscribe_and_join(socket, "user:#{user.id}", %{})
      # Wait for presence tracking
      :timer.sleep(100)
      {:ok, socket: socket}
    end

    test "user can update their status", %{socket: socket, user: user} do
      ref = push(socket, "status_update", %{"status" => "away"})
      assert_reply ref, :ok, %{status: "away"}

      presence = Presence.get_user_presence(user.id)
      [meta | _] = presence.metas
      assert meta.status == "away"
    end

    test "status update broadcasts presence change", %{socket: socket} do
      Phoenix.PubSub.subscribe(Ridex.PubSub, "presence:updates")

      push(socket, "status_update", %{"status" => "busy"})

      assert_receive {:presence_update, %{event: "status_changed", meta: %{status: "busy"}}}
    end
  end

  describe "getting online users" do
    setup %{socket: socket, user: user} do
      {:ok, _, socket} = subscribe_and_join(socket, "user:#{user.id}", %{})
      # Wait for presence tracking
      :timer.sleep(100)
      {:ok, socket: socket}
    end

    test "can get list of online users", %{socket: socket} do
      ref = push(socket, "get_online_users", %{})
      assert_reply ref, :ok, %{users: users}

      assert is_list(users)
    end

    test "can get list of online drivers", %{socket: socket} do
      # Create and track a driver
      driver_user = user_fixture(%{role: :driver})
      {:ok, driver_socket} = connect(RidexWeb.UserSocket, %{"token" => Accounts.generate_user_socket_token(driver_user)})
      {:ok, _, _} = subscribe_and_join(driver_socket, "user:#{driver_user.id}", %{})
      :timer.sleep(100)

      ref = push(socket, "get_online_drivers", %{})
      assert_reply ref, :ok, %{drivers: drivers}

      assert is_list(drivers)
      assert Enum.any?(drivers, fn {user_id, _meta} -> user_id == driver_user.id end)
    end
  end

  describe "ping" do
    setup %{socket: socket, user: user} do
      {:ok, _, socket} = subscribe_and_join(socket, "user:#{user.id}", %{})
      {:ok, socket: socket}
    end

    test "responds to ping with pong", %{socket: socket} do
      ref = push(socket, "ping", %{})
      assert_reply ref, :ok, %{pong: true}
    end

    test "ping updates last_ping timestamp", %{socket: socket, user: user} do
      # Wait for initial presence tracking
      :timer.sleep(100)

      initial_presence = Presence.get_user_presence(user.id)
      [initial_meta | _] = initial_presence.metas

      push(socket, "ping", %{})
      :timer.sleep(50)

      updated_presence = Presence.get_user_presence(user.id)
      [updated_meta | _] = updated_presence.metas

      assert Map.has_key?(updated_meta, :last_ping)
      assert updated_meta.last_ping > (initial_meta[:last_ping] || 0)
    end
  end

  describe "presence events" do
    test "receives presence_state on lobby join", %{socket: socket} do
      {:ok, reply, _socket} = subscribe_and_join(socket, "users:lobby", %{})

      # Should receive presence state in join reply or as a push
      assert_push "presence_state", _state
    end

    test "receives presence_diff when users join/leave", %{socket: socket} do
      {:ok, _, _socket} = subscribe_and_join(socket, "users:lobby", %{})

      # Create another user and have them join
      other_user = user_fixture()
      {:ok, other_socket} = connect(RidexWeb.UserSocket, %{"token" => Accounts.generate_user_socket_token(other_user)})
      {:ok, _, _} = subscribe_and_join(other_socket, "user:#{other_user.id}", %{})

      # Should receive presence diff
      assert_push "presence_diff", %{joins: joins}
      assert Map.has_key?(joins, other_user.id)
    end
  end

  describe "notifications" do
    setup %{socket: socket, user: user} do
      {:ok, _, socket} = subscribe_and_join(socket, "user:#{user.id}", %{})
      {:ok, socket: socket}
    end

    test "receives user notifications", %{socket: socket, user: user} do
      notification = %{
        id: "test_notification",
        type: "test",
        title: "Test Notification",
        message: "This is a test",
        timestamp: System.system_time(:second)
      }

      Phoenix.PubSub.broadcast(Ridex.PubSub, "user:#{user.id}", {:user_notification, notification})

      assert_push "notification", ^notification
    end

    test "receives trip notifications", %{socket: socket, user: user} do
      trip_id = Ecto.UUID.generate()
      event = "trip_accepted"
      data = %{driver_id: Ecto.UUID.generate()}

      Phoenix.PubSub.broadcast(Ridex.PubSub, "user:#{user.id}", {:trip_notification, trip_id, event, data})

      assert_push "trip_notification", %{
        trip_id: ^trip_id,
        event: ^event,
        data: ^data,
        timestamp: _timestamp
      }
    end
  end
end
