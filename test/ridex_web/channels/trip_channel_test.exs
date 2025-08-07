defmodule RidexWeb.TripChannelTest do
  use RidexWeb.ChannelCase, async: true

  alias RidexWeb.{TripChannel, UserSocket}
  alias Ridex.Trips

  import Ridex.AccountsFixtures
  import Ridex.DriversFixtures
  import Ridex.RidersFixtures
  import Ridex.TripsFixtures

  setup do
    # Create driver and rider users
    driver_user = user_fixture(%{role: :driver})
    rider_user = user_fixture(%{role: :rider})

    # Create driver and rider profiles
    driver = driver_fixture(%{
      user: driver_user,
      is_active: true,
      availability_status: :active,
      current_location: %Geo.Point{coordinates: {-74.0050, 40.7120}, srid: 4326}
    })

    rider = rider_fixture(%{user: rider_user})

    # Create a trip
    trip = trip_fixture(%{
      driver_id: driver.id,
      rider_id: rider.id,
      status: :accepted,
      pickup_location: %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}
    })

    %{
      driver_user: driver_user,
      rider_user: rider_user,
      driver: driver,
      rider: rider,
      trip: trip
    }
  end

  describe "join trip channel" do
    test "driver can join their assigned trip channel", %{driver_user: driver_user, trip: trip} do
      {:ok, socket} = connect(UserSocket, %{"token" => generate_user_token(driver_user)})

      assert {:ok, _, socket} = subscribe_and_join(socket, TripChannel, "trip:#{trip.id}")
      assert socket.assigns.trip_id == trip.id
      assert socket.assigns.user_role == :driver
    end

    test "rider can join their assigned trip channel", %{rider_user: rider_user, trip: trip} do
      {:ok, socket} = connect(UserSocket, %{"token" => generate_user_token(rider_user)})

      assert {:ok, _, socket} = subscribe_and_join(socket, TripChannel, "trip:#{trip.id}")
      assert socket.assigns.trip_id == trip.id
      assert socket.assigns.user_role == :rider
    end

    test "unauthorized user cannot join trip channel", %{trip: trip} do
      unauthorized_user = user_fixture(%{role: :rider})
      {:ok, socket} = connect(UserSocket, %{"token" => generate_user_token(unauthorized_user)})

      assert {:error, %{reason: "unauthorized"}} =
        subscribe_and_join(socket, TripChannel, "trip:#{trip.id}")
    end

    test "cannot join non-existent trip channel", %{driver_user: driver_user} do
      {:ok, socket} = connect(UserSocket, %{"token" => generate_user_token(driver_user)})
      fake_trip_id = Ecto.UUID.generate()

      assert {:error, %{reason: "trip_not_found"}} =
        subscribe_and_join(socket, TripChannel, "trip:#{fake_trip_id}")
    end

    test "sends trip info after joining", %{driver_user: driver_user, trip: trip} do
      {:ok, socket} = connect(UserSocket, %{"token" => generate_user_token(driver_user)})

      assert {:ok, _, _socket} = subscribe_and_join(socket, TripChannel, "trip:#{trip.id}")

      assert_push "trip_joined", %{trip: trip_info}
      assert trip_info.id == trip.id
      assert trip_info.status == :accepted
      assert is_map(trip_info.pickup_location)
      assert is_map(trip_info.driver_info)
      assert is_map(trip_info.rider_info)
    end
  end

  describe "trip status updates" do
    test "driver can start trip", %{driver_user: driver_user, trip: trip} do
      {:ok, socket} = connect(UserSocket, %{"token" => generate_user_token(driver_user)})
      {:ok, _, socket} = subscribe_and_join(socket, TripChannel, "trip:#{trip.id}")

      ref = push(socket, "update_trip_status", %{"status" => "start"})
      assert_reply ref, :ok, %{status: "updated", trip_status: :in_progress}

      # Verify trip status was updated in database
      updated_trip = Trips.get_trip(trip.id)
      assert updated_trip.status == :in_progress
      assert updated_trip.started_at != nil

      # Verify broadcast was sent
      assert_broadcast "trip_status_updated", %{
        trip_id: trip_id,
        status: :in_progress,
        updated_by: driver_id
      }
      assert trip_id == trip.id
      assert driver_id == driver_user.id
    end

    test "driver can complete trip", %{driver_user: driver_user, trip: trip} do
      # First start the trip
      {:ok, started_trip} = Ridex.Trips.TripService.start_trip(trip.id, driver_user.id)

      {:ok, socket} = connect(UserSocket, %{"token" => generate_user_token(driver_user)})
      {:ok, _, socket} = subscribe_and_join(socket, TripChannel, "trip:#{started_trip.id}")

      ref = push(socket, "update_trip_status", %{"status" => "complete", "fare" => "25.50"})
      assert_reply ref, :ok, %{status: "updated", trip_status: :completed}

      # Verify trip status was updated in database
      updated_trip = Trips.get_trip(trip.id)
      assert updated_trip.status == :completed
      assert updated_trip.completed_at != nil
      assert updated_trip.fare != nil

      # Verify broadcast was sent
      assert_broadcast "trip_status_updated", %{
        trip_id: trip_id,
        status: :completed
      }
      assert trip_id == trip.id
    end

    test "rider cannot update trip status", %{rider_user: rider_user, trip: trip} do
      {:ok, socket} = connect(UserSocket, %{"token" => generate_user_token(rider_user)})
      {:ok, _, socket} = subscribe_and_join(socket, TripChannel, "trip:#{trip.id}")

      ref = push(socket, "update_trip_status", %{"status" => "start"})
      assert_reply ref, :error, %{reason: "invalid_status_update"}
    end

    test "invalid status update returns error", %{driver_user: driver_user, trip: trip} do
      {:ok, socket} = connect(UserSocket, %{"token" => generate_user_token(driver_user)})
      {:ok, _, socket} = subscribe_and_join(socket, TripChannel, "trip:#{trip.id}")

      ref = push(socket, "update_trip_status", %{"status" => "invalid"})
      assert_reply ref, :error, %{reason: "invalid_status_update"}
    end
  end

  describe "location updates" do
    test "driver can send location updates during active trip", %{driver_user: driver_user, trip: trip} do
      {:ok, socket} = connect(UserSocket, %{"token" => generate_user_token(driver_user)})
      {:ok, _, socket} = subscribe_and_join(socket, TripChannel, "trip:#{trip.id}")

      location_data = %{
        "latitude" => 40.7130,
        "longitude" => -74.0055,
        "accuracy" => 10.0
      }

      ref = push(socket, "location_update", location_data)
      assert_reply ref, :ok, %{status: "location_updated"}

      # Verify broadcast was sent
      assert_broadcast "driver_location_updated", %{
        trip_id: trip_id,
        driver_id: driver_id,
        latitude: 40.7130,
        longitude: -74.0055
      }
      assert trip_id == trip.id
      assert driver_id == driver_user.id
    end

    test "rider cannot send location updates", %{rider_user: rider_user, trip: trip} do
      {:ok, socket} = connect(UserSocket, %{"token" => generate_user_token(rider_user)})
      {:ok, _, socket} = subscribe_and_join(socket, TripChannel, "trip:#{trip.id}")

      location_data = %{
        "latitude" => 40.7130,
        "longitude" => -74.0055
      }

      ref = push(socket, "location_update", location_data)
      assert_reply ref, :error, %{reason: "unauthorized_location_update"}
    end

    test "driver cannot send location updates for completed trip", %{driver_user: driver_user, trip: trip} do
      # Complete the trip first
      completed_trip = trip_fixture(%{
        driver_id: trip.driver_id,
        rider_id: trip.rider_id,
        status: :completed
      })

      {:ok, socket} = connect(UserSocket, %{"token" => generate_user_token(driver_user)})
      {:ok, _, socket} = subscribe_and_join(socket, TripChannel, "trip:#{completed_trip.id}")

      location_data = %{
        "latitude" => 40.7130,
        "longitude" => -74.0055
      }

      ref = push(socket, "location_update", location_data)
      assert_reply ref, :error, %{reason: "unauthorized_location_update"}
    end
  end

  describe "messaging" do
    test "driver can send messages during active trip", %{driver_user: driver_user, trip: trip} do
      {:ok, socket} = connect(UserSocket, %{"token" => generate_user_token(driver_user)})
      {:ok, _, socket} = subscribe_and_join(socket, TripChannel, "trip:#{trip.id}")

      message_data = %{
        "message" => "I'm on my way!",
        "message_type" => "text"
      }

      ref = push(socket, "send_message", message_data)
      assert_reply ref, :ok, %{status: "message_sent"}

      # Verify broadcast was sent
      assert_broadcast "message_received", %{
        trip_id: trip_id,
        sender_id: sender_id,
        sender_role: :driver,
        message: "I'm on my way!",
        message_type: "text"
      }
      assert trip_id == trip.id
      assert sender_id == driver_user.id
    end

    test "rider can send messages during active trip", %{rider_user: rider_user, trip: trip} do
      {:ok, socket} = connect(UserSocket, %{"token" => generate_user_token(rider_user)})
      {:ok, _, socket} = subscribe_and_join(socket, TripChannel, "trip:#{trip.id}")

      message_data = %{
        "message" => "I'll be waiting outside",
        "message_type" => "text"
      }

      ref = push(socket, "send_message", message_data)
      assert_reply ref, :ok, %{status: "message_sent"}

      # Verify broadcast was sent
      assert_broadcast "message_received", %{
        sender_role: :rider,
        message: "I'll be waiting outside"
      }
    end

    test "cannot send messages for completed trip", %{driver_user: driver_user, trip: trip} do
      # Complete the trip first
      completed_trip = trip_fixture(%{
        driver_id: trip.driver_id,
        rider_id: trip.rider_id,
        status: :completed
      })

      {:ok, socket} = connect(UserSocket, %{"token" => generate_user_token(driver_user)})
      {:ok, _, socket} = subscribe_and_join(socket, TripChannel, "trip:#{completed_trip.id}")

      message_data = %{"message" => "Hello"}

      ref = push(socket, "send_message", message_data)
      assert_reply ref, :error, %{reason: "messaging_not_allowed"}
    end
  end

  describe "driver arrival" do
    test "driver can notify arrival", %{driver_user: driver_user, trip: trip} do
      {:ok, socket} = connect(UserSocket, %{"token" => generate_user_token(driver_user)})
      {:ok, _, socket} = subscribe_and_join(socket, TripChannel, "trip:#{trip.id}")

      ref = push(socket, "driver_arrived", %{})
      assert_reply ref, :ok, %{status: "arrival_notified"}

      # Verify broadcast was sent
      assert_broadcast "driver_arrived", %{
        trip_id: trip_id,
        driver_id: driver_id,
        driver_name: driver_name
      }
      assert trip_id == trip.id
      assert driver_id == driver_user.id
      assert driver_name == driver_user.name
    end

    test "rider cannot notify arrival", %{rider_user: rider_user, trip: trip} do
      {:ok, socket} = connect(UserSocket, %{"token" => generate_user_token(rider_user)})
      {:ok, _, socket} = subscribe_and_join(socket, TripChannel, "trip:#{trip.id}")

      ref = push(socket, "driver_arrived", %{})
      assert_reply ref, :error, %{reason: "unauthorized_arrival_notification"}
    end

    test "driver cannot notify arrival for in-progress trip", %{driver_user: driver_user, trip: trip} do
      # Start the trip first
      in_progress_trip = trip_fixture(%{
        driver_id: trip.driver_id,
        rider_id: trip.rider_id,
        status: :in_progress
      })

      {:ok, socket} = connect(UserSocket, %{"token" => generate_user_token(driver_user)})
      {:ok, _, socket} = subscribe_and_join(socket, TripChannel, "trip:#{in_progress_trip.id}")

      ref = push(socket, "driver_arrived", %{})
      assert_reply ref, :error, %{reason: "unauthorized_arrival_notification"}
    end
  end

  describe "trip cancellation" do
    test "driver can cancel trip", %{driver_user: driver_user, trip: trip} do
      {:ok, socket} = connect(UserSocket, %{"token" => generate_user_token(driver_user)})
      {:ok, _, socket} = subscribe_and_join(socket, TripChannel, "trip:#{trip.id}")

      ref = push(socket, "cancel_trip", %{"reason" => "Emergency"})
      assert_reply ref, :ok, %{status: "trip_cancelled"}

      # Verify trip was cancelled in database
      updated_trip = Trips.get_trip(trip.id)
      assert updated_trip.status == :cancelled
      assert updated_trip.cancellation_reason == "Emergency"

      # Verify broadcast was sent
      assert_broadcast "trip_cancelled", %{
        trip_id: trip_id,
        cancelled_by: cancelled_by,
        reason: "Emergency"
      }
      assert trip_id == trip.id
      assert cancelled_by == driver_user.id
    end

    test "rider can cancel trip", %{rider_user: rider_user, trip: trip} do
      {:ok, socket} = connect(UserSocket, %{"token" => generate_user_token(rider_user)})
      {:ok, _, socket} = subscribe_and_join(socket, TripChannel, "trip:#{trip.id}")

      ref = push(socket, "cancel_trip", %{"reason" => "Changed plans"})
      assert_reply ref, :ok, %{status: "trip_cancelled"}

      # Verify broadcast was sent
      assert_broadcast "trip_cancelled", %{
        cancelled_by: cancelled_by,
        reason: "Changed plans"
      }
      assert cancelled_by == rider_user.id
    end
  end

  describe "get trip info" do
    test "can get current trip information", %{driver_user: driver_user, trip: trip} do
      {:ok, socket} = connect(UserSocket, %{"token" => generate_user_token(driver_user)})
      {:ok, _, socket} = subscribe_and_join(socket, TripChannel, "trip:#{trip.id}")

      ref = push(socket, "get_trip_info", %{})
      assert_reply ref, :ok, %{trip: trip_info}

      assert trip_info.id == trip.id
      assert trip_info.status == :accepted
      assert is_map(trip_info.pickup_location)
      assert is_map(trip_info.driver_info)
      assert is_map(trip_info.rider_info)
    end
  end

  # Helper function to generate user tokens for testing
  defp generate_user_token(user) do
    Phoenix.Token.sign(RidexWeb.Endpoint, "user socket", user.id)
  end
end
