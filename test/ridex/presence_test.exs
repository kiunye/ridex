defmodule Ridex.PresenceTest do
  use RidexWeb.ChannelCase

  alias Ridex.Presence
  alias Ridex.Accounts

  import Ridex.AccountsFixtures

  setup do
    user = user_fixture()
    {:ok, socket} = connect(RidexWeb.UserSocket, %{"token" => Accounts.generate_user_socket_token(user)})
    {:ok, _, socket} = subscribe_and_join(socket, "users:lobby", %{})
    {:ok, user: user, socket: socket}
  end

  describe "track_user/3" do
    test "tracks user presence with default metadata", %{socket: socket, user: user} do
      assert {:ok, _} = Presence.track_user(socket, user.id)

      # Give presence time to sync
      :timer.sleep(50)

      presence = Presence.get_user_presence(user.id)
      assert presence != nil

      [meta | _] = presence.metas
      assert meta.user_id == user.id
      assert meta.name == user.name
      assert meta.role == user.role
      assert meta.status == "online"
      assert is_integer(meta.joined_at)
    end

    test "tracks user presence with custom metadata", %{socket: socket, user: user} do
      custom_meta = %{status: "busy", location: "office"}

      assert {:ok, _} = Presence.track_user(socket, user.id, custom_meta)

      # Give presence time to sync
      :timer.sleep(50)

      presence = Presence.get_user_presence(user.id)
      [meta | _] = presence.metas

      assert meta.status == "busy"
      assert meta.location == "office"
      assert meta.user_id == user.id
    end
  end

  describe "user_online?/1" do
    test "returns true when user is tracked", %{socket: socket, user: user} do
      refute Presence.user_online?(user.id)

      Presence.track_user(socket, user.id)
      :timer.sleep(50)

      assert Presence.user_online?(user.id)
    end

    test "returns false when user is not tracked", %{user: user} do
      refute Presence.user_online?(user.id)
    end
  end

  describe "get_online_drivers/0" do
    test "returns only online drivers" do
      driver_user = user_fixture(%{role: :driver})
      rider_user = user_fixture(%{role: :rider})

      {:ok, driver_socket} = connect(RidexWeb.UserSocket, %{"token" => Accounts.generate_user_socket_token(driver_user)})
      {:ok, rider_socket} = connect(RidexWeb.UserSocket, %{"token" => Accounts.generate_user_socket_token(rider_user)})

      {:ok, _, driver_socket} = subscribe_and_join(driver_socket, "users:lobby", %{})
      {:ok, _, rider_socket} = subscribe_and_join(rider_socket, "users:lobby", %{})

      Presence.track_user(driver_socket, driver_user.id)
      Presence.track_user(rider_socket, rider_user.id)
      :timer.sleep(50)

      online_drivers = Presence.get_online_drivers()

      assert length(online_drivers) == 1
      {first_driver_id, _} = List.first(online_drivers)
      assert first_driver_id == driver_user.id
    end
  end

  describe "get_online_riders/0" do
    test "returns only online riders" do
      driver_user = user_fixture(%{role: :driver})
      rider_user = user_fixture(%{role: :rider})

      {:ok, driver_socket} = connect(RidexWeb.UserSocket, %{"token" => Accounts.generate_user_socket_token(driver_user)})
      {:ok, rider_socket} = connect(RidexWeb.UserSocket, %{"token" => Accounts.generate_user_socket_token(rider_user)})

      {:ok, _, driver_socket} = subscribe_and_join(driver_socket, "users:lobby", %{})
      {:ok, _, rider_socket} = subscribe_and_join(rider_socket, "users:lobby", %{})

      Presence.track_user(driver_socket, driver_user.id)
      Presence.track_user(rider_socket, rider_user.id)
      :timer.sleep(50)

      online_riders = Presence.get_online_riders()

      assert length(online_riders) == 1
      {first_rider_id, _} = List.first(online_riders)
      assert first_rider_id == rider_user.id
    end
  end

  describe "update_user_status/3" do
    test "updates user status when user is present", %{socket: socket, user: user} do
      Presence.track_user(socket, user.id)
      :timer.sleep(50)

      assert {:ok, _} = Presence.update_user_status(socket, user.id, "away")
      :timer.sleep(50)

      presence = Presence.get_user_presence(user.id)
      [meta | _] = presence.metas
      assert meta.status == "away"
      assert is_integer(meta.updated_at)
    end

    test "returns error when user is not present", %{socket: socket, user: user} do
      assert {:error, :user_not_present} = Presence.update_user_status(socket, user.id, "away")
    end
  end

  describe "broadcast_presence_update/3" do
    test "broadcasts presence update message" do
      user = user_fixture()

      Phoenix.PubSub.subscribe(Ridex.PubSub, "presence:updates")

      Presence.broadcast_presence_update(user.id, "user_online", %{status: "online"})

      assert_receive {:presence_update, %{user_id: user_id, event: "user_online", meta: %{status: "online"}}}
      assert user_id == user.id
    end
  end
end
