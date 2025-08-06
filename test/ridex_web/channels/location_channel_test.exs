defmodule RidexWeb.LocationChannelTest do
  use RidexWeb.ChannelCase

  alias RidexWeb.LocationChannel
  alias RidexWeb.UserSocket
  alias Ridex.Accounts
  alias Ridex.Drivers
  alias Ridex.LocationService

  import Ridex.AccountsFixtures
  import Ridex.DriversFixtures

  setup do
    user = user_fixture()
    token = Accounts.generate_user_socket_token(user)

    {:ok, socket} = connect(UserSocket, %{"token" => token})
    socket = assign(socket, :current_user, user)

    %{socket: socket, user: user}
  end

  describe "join location:updates" do
    test "authenticated user can join", %{socket: socket} do
      assert {:ok, _, _socket} = subscribe_and_join(socket, LocationChannel, "location:updates")
    end

    test "unauthenticated user cannot join" do
      # Connection should fail without a valid token
      assert :error = connect(UserSocket, %{})
    end
  end

  describe "join location:user:user_id" do
    test "user can join their own channel", %{socket: socket, user: user} do
      assert {:ok, _, _socket} =
        subscribe_and_join(socket, LocationChannel, "location:user:#{user.id}")
    end

    test "user cannot join another user's channel", %{socket: socket} do
      other_user = user_fixture()

      assert {:error, %{reason: "unauthorized"}} =
        subscribe_and_join(socket, LocationChannel, "location:user:#{other_user.id}")
    end
  end

  describe "location_update" do
    test "updates location and broadcasts", %{socket: socket, user: user} do
      {:ok, _, socket} = subscribe_and_join(socket, LocationChannel, "location:updates")

      ref = push(socket, "location_update", %{
        "latitude" => 40.7128,
        "longitude" => -74.0060,
        "accuracy" => 10.5
      })

      assert_reply ref, :ok, %{status: "location_updated"}

      # Check that location was created
      location = LocationService.get_current_location(user.id)
      assert location
      assert Decimal.equal?(location.latitude, Decimal.new("40.7128"))
      assert Decimal.equal?(location.longitude, Decimal.new("-74.0060"))

      # Check that broadcast was sent
      assert_broadcast "location_updated", %{
        user_id: user_id,
        latitude: 40.7128,
        longitude: -74.0060,
        accuracy: 10.5
      }
      assert user_id == user.id
    end

    test "returns error for invalid coordinates", %{socket: socket} do
      {:ok, _, socket} = subscribe_and_join(socket, LocationChannel, "location:updates")

      ref = push(socket, "location_update", %{
        "latitude" => 91.0,  # Invalid latitude
        "longitude" => -74.0060
      })

      assert_reply ref, :error, %{errors: errors}
      assert Map.has_key?(errors, :latitude)
    end
  end

  describe "request_nearby_drivers" do
    test "returns nearby active drivers", %{socket: socket} do
      # Create a driver user and profile
      driver_user = user_fixture(%{role: "driver"})
      {:ok, _driver} = Drivers.create_driver(%{
        user_id: driver_user.id,
        vehicle_info: %{"make" => "Toyota", "model" => "Camry", "year" => 2020},
        license_plate: "ABC123",
        is_active: true,
        availability_status: :active
      })

      # Set driver location
      {:ok, _} = LocationService.update_location(driver_user.id, 40.7128, -74.0060)

      {:ok, _, socket} = subscribe_and_join(socket, LocationChannel, "location:updates")

      ref = push(socket, "request_nearby_drivers", %{
        "latitude" => 40.7128,
        "longitude" => -74.0060,
        "radius_km" => 5.0
      })

      assert_reply ref, :ok, %{drivers: drivers}
      assert length(drivers) == 1

      driver = hd(drivers)
      assert driver.latitude == 40.7128
      assert driver.longitude == -74.0060
      assert driver.vehicle_info
      assert driver.license_plate == "ABC123"
    end

    test "uses default radius when not specified", %{socket: socket} do
      {:ok, _, socket} = subscribe_and_join(socket, LocationChannel, "location:updates")

      ref = push(socket, "request_nearby_drivers", %{
        "latitude" => 40.7128,
        "longitude" => -74.0060
      })

      assert_reply ref, :ok, %{drivers: _drivers}
    end
  end

  describe "driver_checkin" do
    test "driver can check in successfully", %{user: user} do
      # Create driver profile
      {:ok, _driver} = Drivers.create_driver(%{
        user_id: user.id,
        vehicle_info: %{"make" => "Toyota", "model" => "Camry", "year" => 2020},
        license_plate: "ABC123"
      })

      # Update user role to driver
      user = %{user | role: :driver}
      token = Accounts.generate_user_socket_token(user)
      {:ok, socket} = connect(UserSocket, %{"token" => token})
      socket = assign(socket, :current_user, user)

      {:ok, _, socket} = subscribe_and_join(socket, LocationChannel, "location:updates")

      ref = push(socket, "driver_checkin", %{
        "latitude" => 40.7128,
        "longitude" => -74.0060,
        "accuracy" => 10.0
      })

      assert_reply ref, :ok, %{status: "checked_in"}

      # Check that driver is activated
      driver = Drivers.get_driver_by_user_id(user.id)
      assert driver.is_active
      assert driver.availability_status == :active

      # Check that location was updated
      location = LocationService.get_current_location(user.id)
      assert location

      # Check broadcasts
      assert_broadcast "driver_status_changed", %{
        user_id: user_id,
        status: "active"
      }
      assert user_id == user.id

      assert_broadcast "location_updated", %{
        user_id: user_id,
        latitude: 40.7128,
        longitude: -74.0060
      }
      assert user_id == user.id
    end

    test "non-driver cannot check in", %{socket: socket} do
      {:ok, _, socket} = subscribe_and_join(socket, LocationChannel, "location:updates")

      ref = push(socket, "driver_checkin", %{
        "latitude" => 40.7128,
        "longitude" => -74.0060
      })

      assert_reply ref, :error, %{reason: "not_a_driver"}
    end
  end

  describe "driver_checkout" do
    test "driver can check out successfully", %{user: user} do
      # Create and activate driver
      {:ok, driver} = Drivers.create_driver(%{
        user_id: user.id,
        vehicle_info: %{"make" => "Toyota", "model" => "Camry", "year" => 2020},
        license_plate: "ABC123",
        is_active: true,
        availability_status: :active
      })

      # Update user role to driver
      user = %{user | role: :driver}
      token = Accounts.generate_user_socket_token(user)
      {:ok, socket} = connect(UserSocket, %{"token" => token})
      socket = assign(socket, :current_user, user)

      {:ok, _, socket} = subscribe_and_join(socket, LocationChannel, "location:updates")

      ref = push(socket, "driver_checkout", %{})

      assert_reply ref, :ok, %{status: "checked_out"}

      # Check that driver is deactivated
      updated_driver = Drivers.get_driver!(driver.id)
      refute updated_driver.is_active
      assert updated_driver.availability_status == :offline

      # Check broadcast
      assert_broadcast "driver_status_changed", %{
        user_id: user_id,
        status: "offline"
      }
      assert user_id == user.id
    end

    test "non-driver cannot check out", %{socket: socket} do
      {:ok, _, socket} = subscribe_and_join(socket, LocationChannel, "location:updates")

      ref = push(socket, "driver_checkout", %{})

      assert_reply ref, :error, %{reason: "not_a_driver"}
    end
  end

  describe "get_current_location" do
    test "user can get their own location", %{socket: socket, user: user} do
      # Create a location for the user
      {:ok, _} = LocationService.update_location(user.id, 40.7128, -74.0060, 15.0)

      {:ok, _, socket} = subscribe_and_join(socket, LocationChannel, "location:updates")

      ref = push(socket, "get_current_location", %{"user_id" => user.id})

      assert_reply ref, :ok, %{location: location}
      assert location.latitude == 40.7128
      assert location.longitude == -74.0060
      assert location.accuracy == 15.0
    end

    test "user cannot get another user's location", %{socket: socket} do
      other_user = user_fixture()
      {:ok, _} = LocationService.update_location(other_user.id, 40.7128, -74.0060)

      {:ok, _, socket} = subscribe_and_join(socket, LocationChannel, "location:updates")

      ref = push(socket, "get_current_location", %{"user_id" => other_user.id})

      assert_reply ref, :error, %{reason: "unauthorized"}
    end

    test "returns error when location not found", %{socket: socket, user: user} do
      {:ok, _, socket} = subscribe_and_join(socket, LocationChannel, "location:updates")

      ref = push(socket, "get_current_location", %{"user_id" => user.id})

      assert_reply ref, :error, %{reason: "location_not_found"}
    end
  end
end
