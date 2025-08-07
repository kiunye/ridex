defmodule Ridex.Trips.TripServiceTest do
  use Ridex.DataCase

  alias Ridex.Trips.TripService
  alias Ridex.Trips

  import Ridex.DriversFixtures
  import Ridex.RidersFixtures

  describe "create_trip_request/1" do
    @valid_pickup_location %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}
    @valid_destination %Geo.Point{coordinates: {-73.9857, 40.7484}, srid: 4326}

    test "creates trip request with valid data" do
      rider = rider_fixture()

      attrs = %{
        rider_id: rider.user_id,
        pickup_location: @valid_pickup_location,
        destination: @valid_destination
      }

      assert {:ok, trip} = TripService.create_trip_request(attrs)
      assert trip.rider_id == rider.id
      assert trip.pickup_location == @valid_pickup_location
      assert trip.destination == @valid_destination
      assert trip.status == :requested
    end

    test "fails when rider doesn't exist" do
      attrs = %{
        rider_id: Ecto.UUID.generate(),
        pickup_location: @valid_pickup_location
      }

      assert {:error, :rider_not_found} = TripService.create_trip_request(attrs)
    end

    test "fails when rider has too many active trips" do
      rider = rider_fixture()

      # Create maximum allowed active trips
      for _ <- 1..3 do
        {:ok, _trip} = Trips.create_trip_request(%{
          rider_id: rider.id,
          pickup_location: @valid_pickup_location
        })
      end

      # Try to create one more
      attrs = %{
        rider_id: rider.user_id,
        pickup_location: @valid_pickup_location
      }

      assert {:error, :too_many_active_trips} = TripService.create_trip_request(attrs)
    end

    test "fails with invalid pickup location" do
      rider = rider_fixture()

      attrs = %{
        rider_id: rider.user_id,
        pickup_location: "invalid location"
      }

      assert {:error, :invalid_pickup_location} = TripService.create_trip_request(attrs)
    end

    test "fails when pickup location is missing" do
      rider = rider_fixture()

      attrs = %{
        rider_id: rider.user_id
      }

      assert {:error, :pickup_location_required} = TripService.create_trip_request(attrs)
    end
  end

  describe "accept_trip/2" do
    test "accepts trip with valid driver and trip" do
      rider = rider_fixture()
      driver = active_driver_fixture()

      {:ok, trip} = Trips.create_trip_request(%{
        rider_id: rider.id,
        pickup_location: @valid_pickup_location
      })

      assert {:ok, accepted_trip} = TripService.accept_trip(trip.id, driver.user_id)
      assert accepted_trip.status == :accepted
      assert accepted_trip.driver_id == driver.id

      # Driver should now be busy
      updated_driver = Ridex.Drivers.get_driver!(driver.id)
      assert updated_driver.availability_status == :busy
    end

    test "fails when trip doesn't exist" do
      driver = active_driver_fixture()

      assert {:error, :trip_not_found} = TripService.accept_trip(Ecto.UUID.generate(), driver.user_id)
    end

    test "fails when driver doesn't exist" do
      rider = rider_fixture()

      {:ok, trip} = Trips.create_trip_request(%{
        rider_id: rider.id,
        pickup_location: @valid_pickup_location
      })

      assert {:error, :driver_not_found} = TripService.accept_trip(trip.id, Ecto.UUID.generate())
    end

    test "fails when driver is not active" do
      rider = rider_fixture()
      driver = driver_fixture(%{is_active: false})

      {:ok, trip} = Trips.create_trip_request(%{
        rider_id: rider.id,
        pickup_location: @valid_pickup_location
      })

      assert {:error, :driver_not_active} = TripService.accept_trip(trip.id, driver.user_id)
    end

    test "fails when driver already has active trip" do
      rider1 = rider_fixture()
      rider2 = rider_fixture()
      driver = active_driver_fixture()

      # Create and accept first trip
      {:ok, trip1} = Trips.create_trip_request(%{
        rider_id: rider1.id,
        pickup_location: @valid_pickup_location
      })
      {:ok, _} = Trips.accept_trip(trip1, driver.id)

      # Create second trip
      {:ok, trip2} = Trips.create_trip_request(%{
        rider_id: rider2.id,
        pickup_location: @valid_pickup_location
      })

      assert {:error, :driver_has_active_trip} = TripService.accept_trip(trip2.id, driver.user_id)
    end

    test "fails when trip is already accepted" do
      rider = rider_fixture()
      driver1 = active_driver_fixture()
      driver2 = active_driver_fixture()

      {:ok, trip} = Trips.create_trip_request(%{
        rider_id: rider.id,
        pickup_location: @valid_pickup_location
      })

      # First driver accepts
      {:ok, _} = TripService.accept_trip(trip.id, driver1.user_id)

      # Second driver tries to accept
      assert {:error, {:trip_not_available, :accepted}} = TripService.accept_trip(trip.id, driver2.user_id)
    end

    test "fails when trip has expired" do
      rider = rider_fixture()
      driver = active_driver_fixture()

      # Create trip with old timestamp
      old_time = DateTime.utc_now() |> DateTime.add(-5, :minute) |> DateTime.truncate(:second)
      {:ok, trip} = Trips.create_trip_request(%{
        rider_id: rider.id,
        pickup_location: @valid_pickup_location
      })

      # Manually update the requested_at time to be old
      Trips.update_trip(trip, %{requested_at: old_time})

      assert {:error, :trip_expired} = TripService.accept_trip(trip.id, driver.user_id)
    end
  end

  describe "decline_trip/3" do
    test "logs trip decline" do
      rider = rider_fixture()
      driver = active_driver_fixture()

      {:ok, trip} = Trips.create_trip_request(%{
        rider_id: rider.id,
        pickup_location: @valid_pickup_location
      })

      assert :ok = TripService.decline_trip(trip.id, driver.user_id, "Too far")
    end
  end

  describe "start_trip/2" do
    test "starts trip when driver and trip are valid" do
      rider = rider_fixture()
      driver = active_driver_fixture()

      {:ok, trip} = Trips.create_trip_request(%{
        rider_id: rider.id,
        pickup_location: @valid_pickup_location
      })
      {:ok, accepted_trip} = Trips.accept_trip(trip, driver.id)

      assert {:ok, started_trip} = TripService.start_trip(accepted_trip.id, driver.user_id)
      assert started_trip.status == :in_progress
    end

    test "fails when trip is not accepted" do
      rider = rider_fixture()
      driver = active_driver_fixture()

      {:ok, trip} = Trips.create_trip_request(%{
        rider_id: rider.id,
        pickup_location: @valid_pickup_location
      })

      assert {:error, {:invalid_trip_status, :requested}} = TripService.start_trip(trip.id, driver.user_id)
    end

    test "fails when wrong driver tries to start trip" do
      rider = rider_fixture()
      driver1 = active_driver_fixture()
      driver2 = active_driver_fixture()

      {:ok, trip} = Trips.create_trip_request(%{
        rider_id: rider.id,
        pickup_location: @valid_pickup_location
      })
      {:ok, accepted_trip} = Trips.accept_trip(trip, driver1.id)

      result = TripService.start_trip(accepted_trip.id, driver2.user_id)
      assert {:error, {:not_assigned_driver, actual_driver_id}} = result
      assert actual_driver_id == driver1.id
    end
  end

  describe "complete_trip/3" do
    test "completes trip with calculated fare" do
      rider = rider_fixture()
      driver = active_driver_fixture()

      {:ok, trip} = Trips.create_trip_request(%{
        rider_id: rider.id,
        pickup_location: @valid_pickup_location
      })
      {:ok, accepted_trip} = Trips.accept_trip(trip, driver.id)
      {:ok, started_trip} = Trips.start_trip(accepted_trip)

      assert {:ok, completed_trip} = TripService.complete_trip(started_trip.id, driver.user_id)
      assert completed_trip.status == :completed
      assert completed_trip.fare == Decimal.new("5.00")  # Base fare

      # Driver should be back to active
      updated_driver = Ridex.Drivers.get_driver!(driver.id)
      assert updated_driver.availability_status == :active
    end

    test "completes trip with provided fare" do
      rider = rider_fixture()
      driver = active_driver_fixture()

      {:ok, trip} = Trips.create_trip_request(%{
        rider_id: rider.id,
        pickup_location: @valid_pickup_location
      })
      {:ok, accepted_trip} = Trips.accept_trip(trip, driver.id)
      {:ok, started_trip} = Trips.start_trip(accepted_trip)

      custom_fare = Decimal.new("25.50")
      assert {:ok, completed_trip} = TripService.complete_trip(started_trip.id, driver.user_id, %{fare: custom_fare})
      assert completed_trip.fare == custom_fare
    end

    test "fails with invalid fare" do
      rider = rider_fixture()
      driver = active_driver_fixture()

      {:ok, trip} = Trips.create_trip_request(%{
        rider_id: rider.id,
        pickup_location: @valid_pickup_location
      })
      {:ok, accepted_trip} = Trips.accept_trip(trip, driver.id)
      {:ok, started_trip} = Trips.start_trip(accepted_trip)

      assert {:error, :invalid_fare} = TripService.complete_trip(started_trip.id, driver.user_id, %{fare: -10})
    end
  end

  describe "cancel_trip/4" do
    test "rider can cancel their own trip" do
      rider = rider_fixture()

      {:ok, trip} = Trips.create_trip_request(%{
        rider_id: rider.id,
        pickup_location: @valid_pickup_location
      })

      assert {:ok, cancelled_trip} = TripService.cancel_trip(trip.id, rider.user_id, "Changed mind", :rider)
      assert cancelled_trip.status == :cancelled
      assert cancelled_trip.cancellation_reason == "Changed mind"
    end

    test "driver can cancel accepted trip and becomes available again" do
      rider = rider_fixture()
      driver = active_driver_fixture()

      {:ok, trip} = Trips.create_trip_request(%{
        rider_id: rider.id,
        pickup_location: @valid_pickup_location
      })
      {:ok, accepted_trip} = Trips.accept_trip(trip, driver.id)

      assert {:ok, cancelled_trip} = TripService.cancel_trip(accepted_trip.id, driver.user_id, "Emergency", :driver)
      assert cancelled_trip.status == :cancelled

      # Driver should be back to active
      updated_driver = Ridex.Drivers.get_driver!(driver.id)
      assert updated_driver.availability_status == :active
    end

    test "fails when user is not authorized to cancel" do
      rider1 = rider_fixture()
      rider2 = rider_fixture()

      {:ok, trip} = Trips.create_trip_request(%{
        rider_id: rider1.id,
        pickup_location: @valid_pickup_location
      })

      assert {:error, :not_authorized_to_cancel} = TripService.cancel_trip(trip.id, rider2.user_id, "Not my trip", :rider)
    end
  end

  describe "cancel_expired_trips/1" do
    test "cancels expired trip requests" do
      rider = rider_fixture()

      # Create trip with old timestamp
      {:ok, trip} = Trips.create_trip_request(%{
        rider_id: rider.id,
        pickup_location: @valid_pickup_location
      })

      old_time = DateTime.utc_now() |> DateTime.add(-5, :minute) |> DateTime.truncate(:second)
      Trips.update_trip(trip, %{requested_at: old_time})

      assert {1, nil} = TripService.cancel_expired_trips(2)

      updated_trip = Trips.get_trip!(trip.id)
      assert updated_trip.status == :cancelled
      assert updated_trip.cancellation_reason == "Request timeout"
    end
  end

  describe "get_trip_history/3" do
    test "returns trip history for rider" do
      rider = rider_fixture()
      driver = active_driver_fixture()

      # Create and complete a trip
      {:ok, trip} = Trips.create_trip_request(%{
        rider_id: rider.id,
        pickup_location: @valid_pickup_location
      })
      {:ok, accepted_trip} = Trips.accept_trip(trip, driver.id)
      {:ok, started_trip} = Trips.start_trip(accepted_trip)
      {:ok, _completed_trip} = Trips.complete_trip(started_trip, %{fare: Decimal.new("25.00")})

      history = TripService.get_trip_history(rider.user_id, :rider)
      assert length(history) == 1
      assert hd(history).status == :completed
    end

    test "returns trip history for driver" do
      rider = rider_fixture()
      driver = active_driver_fixture()

      # Create and complete a trip
      {:ok, trip} = Trips.create_trip_request(%{
        rider_id: rider.id,
        pickup_location: @valid_pickup_location
      })
      {:ok, accepted_trip} = Trips.accept_trip(trip, driver.id)
      {:ok, started_trip} = Trips.start_trip(accepted_trip)
      {:ok, _completed_trip} = Trips.complete_trip(started_trip, %{fare: Decimal.new("25.00")})

      history = TripService.get_trip_history(driver.user_id, :driver)
      assert length(history) == 1
      assert hd(history).status == :completed
    end

    test "returns empty list for non-existent user" do
      history = TripService.get_trip_history(Ecto.UUID.generate(), :rider)
      assert history == []
    end
  end

  describe "get_trip_statistics/2" do
    test "returns statistics for rider" do
      rider = rider_fixture()
      driver = active_driver_fixture()

      # Create and complete a trip
      {:ok, trip} = Trips.create_trip_request(%{
        rider_id: rider.id,
        pickup_location: @valid_pickup_location
      })
      {:ok, accepted_trip} = Trips.accept_trip(trip, driver.id)
      {:ok, started_trip} = Trips.start_trip(accepted_trip)
      {:ok, _completed_trip} = Trips.complete_trip(started_trip, %{fare: Decimal.new("25.00")})

      stats = TripService.get_trip_statistics(rider.user_id, :rider)
      assert stats.total_trips == 1
      assert stats.completed_trips == 1
      assert stats.cancelled_trips == 0
      assert stats.completion_rate == 1.0
    end

    test "returns statistics for driver" do
      rider = rider_fixture()
      driver = active_driver_fixture()

      # Create and complete a trip
      {:ok, trip} = Trips.create_trip_request(%{
        rider_id: rider.id,
        pickup_location: @valid_pickup_location
      })
      {:ok, accepted_trip} = Trips.accept_trip(trip, driver.id)
      {:ok, started_trip} = Trips.start_trip(accepted_trip)
      {:ok, _completed_trip} = Trips.complete_trip(started_trip, %{fare: Decimal.new("25.00")})

      stats = TripService.get_trip_statistics(driver.user_id, :driver)
      assert stats.total_trips == 1
      assert stats.completed_trips == 1
      assert stats.cancelled_trips == 0
      assert stats.total_earnings == Decimal.new("25.00")
      assert stats.completion_rate == 1.0
      assert stats.average_fare == Decimal.new("25.00")
    end

    test "returns zero statistics for non-existent user" do
      stats = TripService.get_trip_statistics(Ecto.UUID.generate(), :rider)
      assert stats.total_trips == 0
      assert stats.completion_rate == 0.0
    end
  end

  describe "find_available_trips_for_driver/2" do
    test "finds trips near driver location" do
      rider = rider_fixture()
      driver = active_driver_fixture()

      # Create trip at same location as driver
      {:ok, trip} = Trips.create_trip_request(%{
        rider_id: rider.id,
        pickup_location: driver.current_location  # Same location
      })

      available_trips = TripService.find_available_trips_for_driver(driver.user_id, radius_km: 1.0)
      assert length(available_trips) == 1
      assert hd(available_trips).id == trip.id
    end

    test "returns empty list when driver has no location" do
      driver = driver_fixture(%{is_active: true, availability_status: :active, current_location: nil})

      available_trips = TripService.find_available_trips_for_driver(driver.user_id)
      assert available_trips == []
    end

    test "returns empty list for non-existent driver" do
      available_trips = TripService.find_available_trips_for_driver(Ecto.UUID.generate())
      assert available_trips == []
    end
  end
end
