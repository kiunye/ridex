defmodule Ridex.MatchingServiceTest do
  use Ridex.DataCase, async: true

  alias Ridex.MatchingService
  alias Ridex.Trips

  import Ridex.AccountsFixtures
  import Ridex.DriversFixtures
  import Ridex.RidersFixtures
  import Ridex.TripsFixtures

  describe "find_available_drivers/3" do
    test "returns empty list when no drivers are available" do
      result = MatchingService.find_available_drivers(40.7128, -74.0060, 5.0)
      assert result == []
    end

    test "returns available drivers within radius sorted by score" do
      # Create drivers at different distances
      user1 = user_fixture(%{role: :driver})
      user2 = user_fixture(%{role: :driver})
      user3 = user_fixture(%{role: :driver})

      # Driver 1: Close and active
      driver1 = driver_fixture(%{
        user_id: user1.id,
        is_active: true,
        availability_status: :active,
        current_location: %Geo.Point{coordinates: {-74.0050, 40.7120}, srid: 4326}  # ~0.1km away
      })

      # Driver 2: Further but active
      _driver2 = driver_fixture(%{
        user_id: user2.id,
        is_active: true,
        availability_status: :active,
        current_location: %Geo.Point{coordinates: {-74.0200, 40.7200}, srid: 4326}  # ~2km away
      })

      # Driver 3: Close but away status
      _driver3 = driver_fixture(%{
        user_id: user3.id,
        is_active: true,
        availability_status: :away,
        current_location: %Geo.Point{coordinates: {-74.0055, 40.7125}, srid: 4326}  # ~0.15km away
      })

      result = MatchingService.find_available_drivers(40.7128, -74.0060, 5.0)

      assert length(result) == 3

      # Should be sorted by score (driver1 should be first due to distance and active status)
      first_driver = hd(result)
      assert first_driver.driver.id == driver1.id
      assert first_driver.score > 0.8  # High score for close + active
      assert first_driver.distance_km < 1.0
      assert is_integer(first_driver.estimated_arrival_minutes)
    end

    test "excludes drivers with active trips" do
      user = user_fixture(%{role: :driver})
      rider_user = user_fixture(%{role: :rider})
      rider = rider_fixture(%{user_id: rider_user.id})

      driver = driver_fixture(%{
        user_id: user.id,
        is_active: true,
        availability_status: :active,
        current_location: %Geo.Point{coordinates: {-74.0050, 40.7120}, srid: 4326}
      })

      # Create an active trip for this driver
      trip_fixture(%{
        driver_id: driver.id,
        rider_id: rider.id,
        status: :accepted,
        pickup_location: %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}
      })

      result = MatchingService.find_available_drivers(40.7128, -74.0060, 5.0)
      assert result == []
    end

    test "excludes inactive drivers" do
      user = user_fixture(%{role: :driver})

      _driver = driver_fixture(%{
        user_id: user.id,
        is_active: false,  # Inactive
        availability_status: :offline,
        current_location: %Geo.Point{coordinates: {-74.0050, 40.7120}, srid: 4326}
      })

      result = MatchingService.find_available_drivers(40.7128, -74.0060, 5.0)
      assert result == []
    end

    test "handles Geo.Point input format" do
      user = user_fixture(%{role: :driver})

      _driver = driver_fixture(%{
        user_id: user.id,
        is_active: true,
        availability_status: :active,
        current_location: %Geo.Point{coordinates: {-74.0050, 40.7120}, srid: 4326}
      })

      pickup_point = %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}
      result = MatchingService.find_available_drivers(pickup_point, 5.0)

      assert length(result) == 1
    end

    test "returns empty list for invalid input" do
      assert MatchingService.find_available_drivers(nil, 5.0) == []
      assert MatchingService.find_available_drivers("invalid", 5.0) == []
    end
  end

  describe "calculate_driver_score/3" do
    test "calculates higher score for closer drivers" do
      user1 = user_fixture(%{role: :driver})
      user2 = user_fixture(%{role: :driver})

      # Close driver
      close_driver = driver_fixture(%{
        user_id: user1.id,
        availability_status: :active,
        current_location: %Geo.Point{coordinates: {-74.0050, 40.7120}, srid: 4326}  # ~0.1km
      })

      # Far driver
      far_driver = driver_fixture(%{
        user_id: user2.id,
        availability_status: :active,
        current_location: %Geo.Point{coordinates: {-74.0500, 40.7500}, srid: 4326}  # ~5km
      })

      close_score = MatchingService.calculate_driver_score(close_driver, 40.7128, -74.0060)
      far_score = MatchingService.calculate_driver_score(far_driver, 40.7128, -74.0060)

      assert close_score > far_score
      assert close_score > 0.8
      assert far_score < 0.8
    end

    test "gives bonus for active status vs away status" do
      user1 = user_fixture(%{role: :driver})
      user2 = user_fixture(%{role: :driver})

      # Same location, different availability
      location = %Geo.Point{coordinates: {-74.0050, 40.7120}, srid: 4326}

      active_driver = driver_fixture(%{
        user_id: user1.id,
        availability_status: :active,
        current_location: location
      })

      away_driver = driver_fixture(%{
        user_id: user2.id,
        availability_status: :away,
        current_location: location
      })

      active_score = MatchingService.calculate_driver_score(active_driver, 40.7128, -74.0060)
      away_score = MatchingService.calculate_driver_score(away_driver, 40.7128, -74.0060)

      assert active_score > away_score
    end

    test "returns low score for drivers without location" do
      user = user_fixture(%{role: :driver})

      driver = driver_fixture(%{
        user_id: user.id,
        availability_status: :active,
        current_location: nil  # No location
      })

      score = MatchingService.calculate_driver_score(driver, 40.7128, -74.0060)
      assert score < 0.5  # Should be penalized heavily
    end

    test "ensures score stays between 0.0 and 1.0" do
      user = user_fixture(%{role: :driver})

      driver = driver_fixture(%{
        user_id: user.id,
        availability_status: :active,
        current_location: %Geo.Point{coordinates: {-74.0050, 40.7120}, srid: 4326}
      })

      score = MatchingService.calculate_driver_score(driver, 40.7128, -74.0060)
      assert score >= 0.0
      assert score <= 1.0
    end
  end

  describe "notify_drivers_of_request/3" do
    test "successfully notifies available drivers" do
      user1 = user_fixture(%{role: :driver})
      user2 = user_fixture(%{role: :driver})
      rider_user = user_fixture(%{role: :rider})
      rider = rider_fixture(%{user_id: rider_user.id})

      _driver1 = driver_fixture(%{
        user_id: user1.id,
        is_active: true,
        availability_status: :active,
        current_location: %Geo.Point{coordinates: {-74.0050, 40.7120}, srid: 4326}
      })

      _driver2 = driver_fixture(%{
        user_id: user2.id,
        is_active: true,
        availability_status: :active,
        current_location: %Geo.Point{coordinates: {-74.0100, 40.7150}, srid: 4326}
      })

      trip = trip_fixture(%{
        rider_id: rider.id,
        status: :requested,
        pickup_location: %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}
      })

      pickup_location = %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}

      result = MatchingService.notify_drivers_of_request(trip.id, pickup_location)

      assert {:ok, %{drivers_notified: count, notification_ids: ids, drivers: drivers}} = result
      assert count == 2
      assert length(ids) == 2
      assert length(drivers) == 2
    end

    test "returns error when no drivers are available" do
      rider_user = user_fixture(%{role: :rider})
      rider = rider_fixture(%{user_id: rider_user.id})

      trip = trip_fixture(%{
        rider_id: rider.id,
        status: :requested,
        pickup_location: %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}
      })

      pickup_location = %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}

      result = MatchingService.notify_drivers_of_request(trip.id, pickup_location)
      assert result == {:error, :no_drivers_available}
    end

    test "limits number of drivers notified" do
      rider_user = user_fixture(%{role: :rider})
      rider = rider_fixture(%{user_id: rider_user.id})

      # Create 6 drivers
      _drivers = for i <- 1..6 do
        user = user_fixture(%{role: :driver})
        driver_fixture(%{
          user_id: user.id,
          is_active: true,
          availability_status: :active,
          current_location: %Geo.Point{coordinates: {-74.0050 + i * 0.001, 40.7120}, srid: 4326}
        })
      end

      trip = trip_fixture(%{
        rider_id: rider.id,
        status: :requested,
        pickup_location: %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}
      })

      pickup_location = %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}

      # Should only notify max 5 drivers (default limit)
      result = MatchingService.notify_drivers_of_request(trip.id, pickup_location)

      assert {:ok, %{drivers_notified: 5}} = result
    end

    test "respects custom max_drivers option" do
      rider_user = user_fixture(%{role: :rider})
      rider = rider_fixture(%{user_id: rider_user.id})

      # Create 4 drivers
      for i <- 1..4 do
        user = user_fixture(%{role: :driver})
        driver_fixture(%{
          user_id: user.id,
          is_active: true,
          availability_status: :active,
          current_location: %Geo.Point{coordinates: {-74.0050 + i * 0.001, 40.7120}, srid: 4326}
        })
      end

      trip = trip_fixture(%{
        rider_id: rider.id,
        status: :requested,
        pickup_location: %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}
      })

      pickup_location = %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}

      # Limit to 2 drivers
      result = MatchingService.notify_drivers_of_request(trip.id, pickup_location, max_drivers: 2)

      assert {:ok, %{drivers_notified: 2}} = result
    end
  end

  describe "handle_driver_response/3" do
    test "handles trip acceptance successfully" do
      rider_user = user_fixture(%{role: :rider})
      rider = rider_fixture(%{user_id: rider_user.id})

      driver = driver_fixture(%{
        is_active: true,
        availability_status: :active,
        current_location: %Geo.Point{coordinates: {-74.0050, 40.7120}, srid: 4326}
      })

      trip = trip_fixture(%{
        rider_id: rider.id,
        status: :requested,
        pickup_location: %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}
      })

      result = MatchingService.handle_driver_response(trip.id, driver.user.id, :accept)
      assert result == {:ok, :trip_accepted}

      # Verify trip was accepted
      updated_trip = Trips.get_trip(trip.id)
      assert updated_trip.status == :accepted
      assert updated_trip.driver_id == driver.id
    end

    test "handles trip decline successfully" do
      user = user_fixture(%{role: :driver})
      rider_user = user_fixture(%{role: :rider})
      rider = rider_fixture(%{user_id: rider_user.id})

      _driver = driver_fixture(%{
        user_id: user.id,
        is_active: true,
        availability_status: :active,
        current_location: %Geo.Point{coordinates: {-74.0050, 40.7120}, srid: 4326}
      })

      trip = trip_fixture(%{
        rider_id: rider.id,
        status: :requested,
        pickup_location: %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}
      })

      result = MatchingService.handle_driver_response(trip.id, user.id, :decline)
      assert result == {:ok, :trip_declined}

      # Verify trip is still in requested status
      updated_trip = Trips.get_trip(trip.id)
      assert updated_trip.status == :requested
      assert is_nil(updated_trip.driver_id)
    end

    test "returns error for invalid response" do
      user = user_fixture(%{role: :driver})
      rider_user = user_fixture(%{role: :rider})
      rider = rider_fixture(%{user_id: rider_user.id})

      trip = trip_fixture(%{
        rider_id: rider.id,
        status: :requested,
        pickup_location: %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}
      })

      result = MatchingService.handle_driver_response(trip.id, user.id, :invalid)
      assert result == {:error, :invalid_response}
    end

    test "returns error when driver tries to accept already accepted trip" do
      user1 = user_fixture(%{role: :driver})
      user2 = user_fixture(%{role: :driver})
      rider_user = user_fixture(%{role: :rider})
      rider = rider_fixture(%{user_id: rider_user.id})

      driver1 = driver_fixture(%{
        user_id: user1.id,
        is_active: true,
        availability_status: :active,
        current_location: %Geo.Point{coordinates: {-74.0050, 40.7120}, srid: 4326}
      })

      _driver2 = driver_fixture(%{
        user_id: user2.id,
        is_active: true,
        availability_status: :active,
        current_location: %Geo.Point{coordinates: {-74.0100, 40.7150}, srid: 4326}
      })

      trip = trip_fixture(%{
        rider_id: rider.id,
        driver_id: driver1.id,  # Already accepted by driver1
        status: :accepted,
        pickup_location: %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}
      })

      # Driver2 tries to accept already accepted trip
      result = MatchingService.handle_driver_response(trip.id, user2.id, :accept)
      assert {:error, _reason} = result
    end
  end

  describe "retry_with_expanded_radius/2" do
    test "expands search radius when no drivers found initially" do
      rider_user = user_fixture(%{role: :rider})
      rider = rider_fixture(%{user_id: rider_user.id})

      # Create a driver far away (outside initial 5km radius but within 10km)
      user = user_fixture(%{role: :driver})
      _driver = driver_fixture(%{
        user_id: user.id,
        is_active: true,
        availability_status: :active,
        current_location: %Geo.Point{coordinates: {-74.0800, 40.7800}, srid: 4326}  # ~8km away
      })

      trip = trip_fixture(%{
        rider_id: rider.id,
        status: :requested,
        pickup_location: %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}
      })

      result = MatchingService.retry_with_expanded_radius(trip.id, 5.0)

      assert {:ok, %{drivers_notified: 1, expanded_radius: 10.0}} = result
    end

    test "returns error when trip not found" do
      non_existent_trip_id = Ecto.UUID.generate()
      result = MatchingService.retry_with_expanded_radius(non_existent_trip_id)
      assert result == {:error, :trip_not_found}
    end

    test "returns error when trip is not in requested status" do
      rider_user = user_fixture(%{role: :rider})
      rider = rider_fixture(%{user_id: rider_user.id})

      trip = trip_fixture(%{
        rider_id: rider.id,
        status: :completed,  # Not requested
        pickup_location: %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}
      })

      result = MatchingService.retry_with_expanded_radius(trip.id)
      assert result == {:error, {:trip_not_available, :completed}}
    end
  end

  describe "get_matching_statistics/1" do
    test "returns statistics structure" do
      stats = MatchingService.get_matching_statistics()

      assert is_map(stats)
      assert Map.has_key?(stats, :average_match_time_seconds)
      assert Map.has_key?(stats, :success_rate)
      assert Map.has_key?(stats, :average_drivers_per_request)
      assert Map.has_key?(stats, :total_requests)
      assert Map.has_key?(stats, :successful_matches)
    end

    test "accepts hours_back parameter" do
      stats = MatchingService.get_matching_statistics(48)
      assert is_map(stats)
    end
  end
end
