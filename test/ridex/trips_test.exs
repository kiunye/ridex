defmodule Ridex.TripsTest do
  use Ridex.DataCase

  alias Ridex.Trips
  alias Ridex.Trips.Trip

  import Ridex.DriversFixtures
  import Ridex.RidersFixtures

  describe "trips" do
    @valid_pickup_location %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}
    @valid_destination %Geo.Point{coordinates: {-73.9857, 40.7484}, srid: 4326}

    @valid_attrs %{
      pickup_location: @valid_pickup_location,
      destination: @valid_destination
    }

    @invalid_attrs %{pickup_location: nil, destination: nil}

    def trip_fixture(attrs \\ %{}) do
      # Only create a rider if rider_id is not provided
      attrs_with_defaults = Enum.into(attrs, @valid_attrs)

      final_attrs = case Map.get(attrs_with_defaults, :rider_id) do
        nil ->
          rider = rider_fixture()
          Map.put(attrs_with_defaults, :rider_id, rider.id)
        _ ->
          attrs_with_defaults
      end

      {:ok, trip} = Trips.create_trip_request(final_attrs)
      trip
    end

    test "list_trips/0 returns all trips" do
      trip = trip_fixture()
      assert Trips.list_trips() == [trip]
    end

    test "get_trip!/1 returns the trip with given id" do
      trip = trip_fixture()
      assert Trips.get_trip!(trip.id) == trip
    end

    test "get_trip/1 returns the trip with given id" do
      trip = trip_fixture()
      assert Trips.get_trip(trip.id) == trip
    end

    test "get_trip/1 returns nil for non-existent id" do
      assert Trips.get_trip(Ecto.UUID.generate()) == nil
    end

    test "get_trip_with_associations/1 returns trip with preloaded associations" do
      trip = trip_fixture()
      result = Trips.get_trip_with_associations(trip.id)

      assert result.id == trip.id
      assert %Ridex.Riders.Rider{} = result.rider
      assert result.driver == nil  # No driver assigned yet
    end

    test "create_trip_request/1 with valid data creates a trip" do
      rider = rider_fixture()
      valid_attrs = Map.put(@valid_attrs, :rider_id, rider.id)

      assert {:ok, %Trip{} = trip} = Trips.create_trip_request(valid_attrs)
      assert trip.pickup_location == @valid_pickup_location
      assert trip.destination == @valid_destination
      assert trip.status == :requested
      assert trip.rider_id == rider.id
      assert trip.driver_id == nil
      assert %DateTime{} = trip.requested_at
    end

    test "create_trip_request/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Trips.create_trip_request(@invalid_attrs)
    end

    test "accept_trip/2 assigns driver and changes status to accepted" do
      trip = trip_fixture()
      driver = driver_fixture()

      assert {:ok, %Trip{} = updated_trip} = Trips.accept_trip(trip, driver.id)
      assert updated_trip.driver_id == driver.id
      assert updated_trip.status == :accepted
      assert %DateTime{} = updated_trip.accepted_at
    end

    test "accept_trip/2 fails if trip is not in requested status" do
      trip = trip_fixture()
      driver = driver_fixture()

      # First accept the trip
      {:ok, accepted_trip} = Trips.accept_trip(trip, driver.id)

      # Try to accept again with different driver
      other_driver = driver_fixture()
      assert {:error, %Ecto.Changeset{}} = Trips.accept_trip(accepted_trip, other_driver.id)
    end

    test "start_trip/1 changes status to in_progress" do
      trip = trip_fixture()
      driver = driver_fixture()

      {:ok, accepted_trip} = Trips.accept_trip(trip, driver.id)
      assert {:ok, %Trip{} = started_trip} = Trips.start_trip(accepted_trip)

      assert started_trip.status == :in_progress
      assert %DateTime{} = started_trip.started_at
    end

    test "start_trip/1 fails if trip is not accepted" do
      trip = trip_fixture()
      assert {:error, %Ecto.Changeset{}} = Trips.start_trip(trip)
    end

    test "complete_trip/2 changes status to completed" do
      trip = trip_fixture()
      driver = driver_fixture()

      {:ok, accepted_trip} = Trips.accept_trip(trip, driver.id)
      {:ok, started_trip} = Trips.start_trip(accepted_trip)

      assert {:ok, %Trip{} = completed_trip} = Trips.complete_trip(started_trip, %{fare: Decimal.new("25.50")})

      assert completed_trip.status == :completed
      assert completed_trip.fare == Decimal.new("25.50")
      assert %DateTime{} = completed_trip.completed_at
    end

    test "complete_trip/2 fails if trip is not in progress" do
      trip = trip_fixture()
      assert {:error, %Ecto.Changeset{}} = Trips.complete_trip(trip, %{fare: Decimal.new("25.50")})
    end

    test "complete_trip/2 fails with negative fare" do
      trip = trip_fixture()
      driver = driver_fixture()

      {:ok, accepted_trip} = Trips.accept_trip(trip, driver.id)
      {:ok, started_trip} = Trips.start_trip(accepted_trip)

      assert {:error, %Ecto.Changeset{}} = Trips.complete_trip(started_trip, %{fare: Decimal.new("-10.00")})
    end

    test "cancel_trip/2 changes status to cancelled" do
      trip = trip_fixture()
      reason = "Driver unavailable"

      assert {:ok, %Trip{} = cancelled_trip} = Trips.cancel_trip(trip, reason)

      assert cancelled_trip.status == :cancelled
      assert cancelled_trip.cancellation_reason == reason
      assert %DateTime{} = cancelled_trip.cancelled_at
    end

    test "cancel_trip/2 can cancel accepted trip" do
      trip = trip_fixture()
      driver = driver_fixture()

      {:ok, accepted_trip} = Trips.accept_trip(trip, driver.id)

      assert {:ok, %Trip{} = cancelled_trip} = Trips.cancel_trip(accepted_trip, "Emergency")
      assert cancelled_trip.status == :cancelled
    end

    test "cancel_trip/2 can cancel in_progress trip" do
      trip = trip_fixture()
      driver = driver_fixture()

      {:ok, accepted_trip} = Trips.accept_trip(trip, driver.id)
      {:ok, started_trip} = Trips.start_trip(accepted_trip)

      assert {:ok, %Trip{} = cancelled_trip} = Trips.cancel_trip(started_trip, "Emergency")
      assert cancelled_trip.status == :cancelled
    end

    test "cancel_trip/2 fails for completed trip" do
      trip = trip_fixture()
      driver = driver_fixture()

      {:ok, accepted_trip} = Trips.accept_trip(trip, driver.id)
      {:ok, started_trip} = Trips.start_trip(accepted_trip)
      {:ok, completed_trip} = Trips.complete_trip(started_trip, %{fare: Decimal.new("25.50")})

      assert {:error, %Ecto.Changeset{}} = Trips.cancel_trip(completed_trip, "Too late")
    end

    test "update_trip/2 with valid data updates the trip" do
      trip = trip_fixture()
      update_attrs = %{destination: %Geo.Point{coordinates: {-73.9442, 40.8176}, srid: 4326}}

      assert {:ok, %Trip{} = updated_trip} = Trips.update_trip(trip, update_attrs)
      assert updated_trip.destination == update_attrs.destination
    end

    test "update_trip/2 with invalid data returns error changeset" do
      trip = trip_fixture()
      assert {:error, %Ecto.Changeset{}} = Trips.update_trip(trip, @invalid_attrs)
      assert trip == Trips.get_trip!(trip.id)
    end

    test "delete_trip/1 deletes the trip" do
      trip = trip_fixture()
      assert {:ok, %Trip{}} = Trips.delete_trip(trip)
      assert_raise Ecto.NoResultsError, fn -> Trips.get_trip!(trip.id) end
    end

    test "change_trip/1 returns a trip changeset" do
      trip = trip_fixture()
      assert %Ecto.Changeset{} = Trips.change_trip(trip)
    end
  end

  describe "trip queries" do
    test "get_active_trips_for_driver/1 returns active trips for driver" do
      driver = driver_fixture()
      trip1 = trip_fixture()
      trip2 = trip_fixture()

      # Accept both trips with the same driver
      {:ok, accepted_trip1} = Trips.accept_trip(trip1, driver.id)
      {:ok, _accepted_trip2} = Trips.accept_trip(trip2, driver.id)

      # Start one trip
      {:ok, _started_trip} = Trips.start_trip(accepted_trip1)

      active_trips = Trips.get_active_trips_for_driver(driver.id)
      assert length(active_trips) == 2

      trip_ids = Enum.map(active_trips, & &1.id)
      assert trip1.id in trip_ids
      assert trip2.id in trip_ids
    end

    test "get_active_trips_for_rider/1 returns active trips for rider" do
      rider = rider_fixture()
      trip = trip_fixture(%{rider_id: rider.id})

      active_trips = Trips.get_active_trips_for_rider(rider.id)
      assert length(active_trips) == 1
      assert hd(active_trips).id == trip.id
    end

    test "get_pending_trip_requests/0 returns unaccepted trip requests" do
      trip1 = trip_fixture()
      trip2 = trip_fixture()
      driver = driver_fixture()

      # Accept one trip
      {:ok, _accepted_trip} = Trips.accept_trip(trip1, driver.id)

      pending_trips = Trips.get_pending_trip_requests()
      assert length(pending_trips) == 1
      assert hd(pending_trips).id == trip2.id
    end

    test "get_trip_requests_near_location/3 returns trips within radius" do
      # Create trip at specific location
      pickup_location = %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}  # NYC
      trip = trip_fixture(%{pickup_location: pickup_location})

      # Search near the same location
      nearby_trips = Trips.get_trip_requests_near_location(40.7128, -74.0060, 1.0)
      assert length(nearby_trips) == 1
      assert hd(nearby_trips).id == trip.id

      # Search far away
      far_trips = Trips.get_trip_requests_near_location(34.0522, -118.2437, 1.0)  # LA
      assert length(far_trips) == 0
    end

    test "driver_has_active_trip?/1 returns true when driver has active trip" do
      driver = driver_fixture()
      trip = trip_fixture()

      refute Trips.driver_has_active_trip?(driver.id)

      {:ok, _accepted_trip} = Trips.accept_trip(trip, driver.id)
      assert Trips.driver_has_active_trip?(driver.id)
    end

    test "rider_has_active_trip?/1 returns true when rider has active trip" do
      rider = rider_fixture()
      _trip = trip_fixture(%{rider_id: rider.id})

      assert Trips.rider_has_active_trip?(rider.id)
    end

    test "cancel_expired_trip_requests/1 cancels old requests" do
      # Create an old trip by manually setting requested_at
      trip = trip_fixture()
      old_time = DateTime.utc_now() |> DateTime.add(-5, :minute)

      # Update the trip to have an old requested_at time
      Trips.update_trip(trip, %{requested_at: old_time})

      # Cancel expired trips (older than 2 minutes)
      {count, _} = Trips.cancel_expired_trip_requests(2)
      assert count == 1

      # Verify the trip was cancelled
      updated_trip = Trips.get_trip!(trip.id)
      assert updated_trip.status == :cancelled
      assert updated_trip.cancellation_reason == "Request timeout"
    end
  end

  describe "trip statistics" do
    test "get_driver_trip_stats/1 returns correct statistics" do
      driver = driver_fixture()

      # Create and complete some trips
      trip1 = trip_fixture()
      trip2 = trip_fixture()
      trip3 = trip_fixture()

      {:ok, accepted_trip1} = Trips.accept_trip(trip1, driver.id)
      {:ok, started_trip1} = Trips.start_trip(accepted_trip1)
      {:ok, _completed_trip1} = Trips.complete_trip(started_trip1, %{fare: Decimal.new("25.00")})

      {:ok, accepted_trip2} = Trips.accept_trip(trip2, driver.id)
      {:ok, started_trip2} = Trips.start_trip(accepted_trip2)
      {:ok, _completed_trip2} = Trips.complete_trip(started_trip2, %{fare: Decimal.new("30.00")})

      {:ok, accepted_trip3} = Trips.accept_trip(trip3, driver.id)
      {:ok, _cancelled_trip3} = Trips.cancel_trip(accepted_trip3, "Emergency")

      stats = Trips.get_driver_trip_stats(driver.id)
      assert stats.total_trips == 3
      assert stats.completed_trips == 2
      assert stats.cancelled_trips == 1
      assert stats.total_earnings == Decimal.new("55.00")
    end

    test "get_rider_trip_stats/1 returns correct statistics" do
      rider = rider_fixture()
      driver = driver_fixture()

      trip1 = trip_fixture(%{rider_id: rider.id})
      trip2 = trip_fixture(%{rider_id: rider.id})

      {:ok, accepted_trip1} = Trips.accept_trip(trip1, driver.id)
      {:ok, started_trip1} = Trips.start_trip(accepted_trip1)
      {:ok, _completed_trip1} = Trips.complete_trip(started_trip1, %{fare: Decimal.new("25.00")})

      {:ok, _cancelled_trip2} = Trips.cancel_trip(trip2, "Changed mind")

      stats = Trips.get_rider_trip_stats(rider.id)
      assert stats.total_trips == 2
      assert stats.completed_trips == 1
      assert stats.cancelled_trips == 1
    end
  end
end
