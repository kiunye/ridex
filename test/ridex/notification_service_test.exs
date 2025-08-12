defmodule Ridex.NotificationServiceTest do
  use RidexWeb.ChannelCase

  alias Ridex.NotificationService
  alias Ridex.Presence
  alias Ridex.Accounts

  import Ridex.AccountsFixtures

  describe "notify_user/2" do
    test "broadcasts notification to specific user" do
      user = user_fixture()
      notification = %{
        id: "test_notification",
        type: "test",
        title: "Test",
        message: "Test message"
      }

      Phoenix.PubSub.subscribe(Ridex.PubSub, "user:#{user.id}")

      NotificationService.notify_user(user.id, notification)

      assert_receive {:user_notification, ^notification}
    end
  end

  describe "notify_trip_event/4" do
    test "broadcasts trip notification to user" do
      user = user_fixture()
      trip_id = Ecto.UUID.generate()
      event = "trip_accepted"
      data = %{driver_id: Ecto.UUID.generate()}

      Phoenix.PubSub.subscribe(Ridex.PubSub, "user:#{user.id}")

      NotificationService.notify_trip_event(user.id, trip_id, event, data)

      assert_receive {:trip_notification, ^trip_id, ^event, ^data}
    end
  end

  describe "create_notification/4" do
    test "creates notification with required fields" do
      notification = NotificationService.create_notification(
        "test_type",
        "Test Title",
        "Test message"
      )

      assert notification.type == "test_type"
      assert notification.title == "Test Title"
      assert notification.message == "Test message"
      assert notification.data == %{}
      assert notification.read == false
      assert is_binary(notification.id)
      assert is_integer(notification.timestamp)
    end

    test "creates notification with custom data" do
      data = %{custom_field: "value"}

      notification = NotificationService.create_notification(
        "test_type",
        "Test Title",
        "Test message",
        data
      )

      assert notification.data == data
    end
  end

  describe "notify_ride_request/4" do
    test "sends ride request notifications to multiple drivers" do
      driver1 = user_fixture(%{role: :driver})
      driver2 = user_fixture(%{role: :driver})
      trip_id = Ecto.UUID.generate()
      pickup_location = %{latitude: 40.7128, longitude: -74.0060}
      rider_name = "John Doe"

      Phoenix.PubSub.subscribe(Ridex.PubSub, "user:#{driver1.id}")
      Phoenix.PubSub.subscribe(Ridex.PubSub, "user:#{driver2.id}")

      NotificationService.notify_ride_request(
        [driver1.id, driver2.id],
        trip_id,
        pickup_location,
        rider_name
      )

      # Should receive notification for both drivers
      assert_receive {:user_notification, notification1}
      assert_receive {:user_notification, notification2}

      assert notification1.type == "ride_request"
      assert notification1.title == "New Ride Request"
      assert notification1.message == "#{rider_name} is requesting a ride nearby"
      assert notification1.data.trip_id == trip_id
      assert notification1.data.action_required == true

      assert notification2.type == "ride_request"
      assert notification2.data.trip_id == trip_id
    end
  end

  describe "notify_trip_status_change/3" do
    setup do
      driver = user_fixture(%{role: :driver})
      rider = user_fixture(%{role: :rider})

      trip = %{
        id: Ecto.UUID.generate(),
        driver_id: driver.id,
        rider_id: rider.id
      }

      {:ok, driver: driver, rider: rider, trip: trip}
    end

    test "notifies rider when trip is accepted", %{trip: trip} do
      Phoenix.PubSub.subscribe(Ridex.PubSub, "user:#{trip.rider_id}")

      NotificationService.notify_trip_status_change(trip, :requested, :accepted)

      assert_receive {:user_notification, notification}
      assert notification.type == "trip_accepted"
      assert notification.title == "Ride Accepted!"
      assert notification.data.trip_id == trip.id
      assert notification.data.driver_id == trip.driver_id
    end

    test "notifies rider when trip starts", %{trip: trip} do
      Phoenix.PubSub.subscribe(Ridex.PubSub, "user:#{trip.rider_id}")

      NotificationService.notify_trip_status_change(trip, :accepted, :in_progress)

      assert_receive {:user_notification, notification}
      assert notification.type == "trip_started"
      assert notification.title == "Trip Started"
    end

    test "notifies both users when trip is completed", %{trip: trip} do
      Phoenix.PubSub.subscribe(Ridex.PubSub, "user:#{trip.rider_id}")
      Phoenix.PubSub.subscribe(Ridex.PubSub, "user:#{trip.driver_id}")

      NotificationService.notify_trip_status_change(trip, :in_progress, :completed)

      # Should receive notifications for both rider and driver
      assert_receive {:user_notification, rider_notification}
      assert_receive {:user_notification, driver_notification}

      assert rider_notification.type == "trip_completed"
      assert rider_notification.data.rating_required == true

      assert driver_notification.type == "trip_completed"
      refute Map.has_key?(driver_notification.data, :rating_required)
    end

    test "notifies users when trip is cancelled", %{trip: trip} do
      Phoenix.PubSub.subscribe(Ridex.PubSub, "user:#{trip.rider_id}")
      Phoenix.PubSub.subscribe(Ridex.PubSub, "user:#{trip.driver_id}")

      NotificationService.notify_trip_status_change(trip, :accepted, :cancelled)

      # Should receive notifications for both users
      assert_receive {:user_notification, rider_notification}
      assert_receive {:user_notification, driver_notification}

      assert rider_notification.type == "trip_cancelled"
      assert driver_notification.type == "trip_cancelled"
    end

    test "notifies rider when no driver found", %{trip: trip} do
      Phoenix.PubSub.subscribe(Ridex.PubSub, "user:#{trip.rider_id}")

      NotificationService.notify_trip_status_change(trip, :requested, :cancelled)

      assert_receive {:user_notification, notification}
      assert notification.type == "trip_cancelled"
      assert notification.title == "No Driver Found"
    end
  end

  describe "notify_driver_status_change/3" do
    test "notifies driver when going active" do
      driver = user_fixture(%{role: :driver})

      Phoenix.PubSub.subscribe(Ridex.PubSub, "user:#{driver.id}")

      NotificationService.notify_driver_status_change(driver.id, "inactive", "active")

      assert_receive {:user_notification, notification}
      assert notification.type == "status_change"
      assert notification.title == "You're Online"
      assert notification.data.status == "active"
    end

    test "notifies driver when going inactive" do
      driver = user_fixture(%{role: :driver})

      Phoenix.PubSub.subscribe(Ridex.PubSub, "user:#{driver.id}")

      NotificationService.notify_driver_status_change(driver.id, "active", "inactive")

      assert_receive {:user_notification, notification}
      assert notification.type == "status_change"
      assert notification.title == "You're Offline"
      assert notification.data.status == "inactive"
    end
  end
end
