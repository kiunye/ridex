defmodule Ridex.LocationsTest do
  use Ridex.DataCase

  alias Ridex.Locations
  alias Ridex.Locations.Location

  import Ridex.AccountsFixtures

  describe "create_location/1" do
    test "creates location with valid attributes" do
      user = user_fixture()
      attrs = %{
        user_id: user.id,
        latitude: Decimal.new("40.7128"),
        longitude: Decimal.new("-74.0060"),
        accuracy: Decimal.new("10.5")
      }

      assert {:ok, %Location{} = location} = Locations.create_location(attrs)
      assert location.user_id == user.id
      assert Decimal.equal?(location.latitude, Decimal.new("40.7128"))
      assert Decimal.equal?(location.longitude, Decimal.new("-74.0060"))
      assert Decimal.equal?(location.accuracy, Decimal.new("10.5"))
      assert location.recorded_at
    end

    test "requires user_id, latitude, and longitude" do
      assert {:error, changeset} = Locations.create_location(%{})
      assert %{user_id: ["can't be blank"], latitude: ["can't be blank"], longitude: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates latitude range" do
      user = user_fixture()

      # Test invalid latitude (too high)
      assert {:error, changeset} = Locations.create_location(%{
        user_id: user.id,
        latitude: Decimal.new("91.0"),
        longitude: Decimal.new("-74.0060")
      })
      assert %{latitude: ["must be between -90 and 90 degrees"]} = errors_on(changeset)

      # Test invalid latitude (too low)
      assert {:error, changeset} = Locations.create_location(%{
        user_id: user.id,
        latitude: Decimal.new("-91.0"),
        longitude: Decimal.new("-74.0060")
      })
      assert %{latitude: ["must be between -90 and 90 degrees"]} = errors_on(changeset)
    end

    test "validates longitude range" do
      user = user_fixture()

      # Test invalid longitude (too high)
      assert {:error, changeset} = Locations.create_location(%{
        user_id: user.id,
        latitude: Decimal.new("40.7128"),
        longitude: Decimal.new("181.0")
      })
      assert %{longitude: ["must be between -180 and 180 degrees"]} = errors_on(changeset)

      # Test invalid longitude (too low)
      assert {:error, changeset} = Locations.create_location(%{
        user_id: user.id,
        latitude: Decimal.new("40.7128"),
        longitude: Decimal.new("-181.0")
      })
      assert %{longitude: ["must be between -180 and 180 degrees"]} = errors_on(changeset)
    end

    test "validates accuracy is positive" do
      user = user_fixture()

      assert {:error, changeset} = Locations.create_location(%{
        user_id: user.id,
        latitude: Decimal.new("40.7128"),
        longitude: Decimal.new("-74.0060"),
        accuracy: Decimal.new("-5.0")
      })
      assert %{accuracy: ["must be greater than 0"]} = errors_on(changeset)
    end
  end

  describe "update_user_location/4" do
    test "creates location with current timestamp" do
      user = user_fixture()

      assert {:ok, %Location{} = location} = Locations.update_user_location(user.id, 40.7128, -74.0060, 10.5)
      assert location.user_id == user.id
      assert Decimal.equal?(location.latitude, Decimal.new("40.7128"))
      assert Decimal.equal?(location.longitude, Decimal.new("-74.0060"))
      assert Decimal.equal?(location.accuracy, Decimal.new("10.5"))

      # Check that recorded_at is recent
      assert DateTime.diff(DateTime.utc_now(), location.recorded_at, :second) < 5
    end

    test "works without accuracy" do
      user = user_fixture()

      assert {:ok, %Location{} = location} = Locations.update_user_location(user.id, 40.7128, -74.0060)
      assert location.user_id == user.id
      assert is_nil(location.accuracy)
    end
  end

  describe "get_latest_location/1" do
    test "returns most recent location for user" do
      user = user_fixture()

      # Create locations with explicit timestamps
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      earlier = DateTime.add(now, -60, :second)

      {:ok, _old_location} = Locations.create_location(%{
        user_id: user.id,
        latitude: Decimal.new("40.0"),
        longitude: Decimal.new("-74.0"),
        recorded_at: earlier
      })

      {:ok, latest_location} = Locations.create_location(%{
        user_id: user.id,
        latitude: Decimal.new("41.0"),
        longitude: Decimal.new("-75.0"),
        recorded_at: now
      })

      result = Locations.get_latest_location(user.id)
      assert result.id == latest_location.id
      assert Decimal.equal?(result.latitude, Decimal.new("41.0"))
    end

    test "returns nil for non-existent user" do
      assert is_nil(Locations.get_latest_location(Ecto.UUID.generate()))
    end
  end

  describe "get_location_history/3" do
    test "returns locations within time range" do
      user = user_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      one_hour_ago = DateTime.add(now, -3600, :second)
      two_hours_ago = DateTime.add(now, -7200, :second)

      # Create locations at different times
      {:ok, _old_location} = Locations.create_location(%{
        user_id: user.id,
        latitude: Decimal.new("40.0"),
        longitude: Decimal.new("-74.0"),
        recorded_at: two_hours_ago
      })

      {:ok, recent_location} = Locations.create_location(%{
        user_id: user.id,
        latitude: Decimal.new("41.0"),
        longitude: Decimal.new("-75.0"),
        recorded_at: one_hour_ago
      })

      # Query for last hour only
      results = Locations.get_location_history(user.id, one_hour_ago, now)

      assert length(results) == 1
      assert hd(results).id == recent_location.id
    end
  end

  describe "find_users_within_radius/3" do
    test "finds users within specified radius" do
      # Create users at different locations
      user1 = user_fixture()
      user2 = user_fixture()
      user3 = user_fixture()

      # New York area (center point)
      {:ok, _} = Locations.update_user_location(user1.id, 40.7128, -74.0060)

      # Close to New York (within 5km)
      {:ok, _} = Locations.update_user_location(user2.id, 40.7200, -74.0100)

      # Far from New York (Los Angeles)
      {:ok, _} = Locations.update_user_location(user3.id, 34.0522, -118.2437)

      # Search within 10km of New York
      results = Locations.find_users_within_radius(40.7128, -74.0060, 10.0)

      user_ids = Enum.map(results, & &1.user_id)
      assert user1.id in user_ids
      assert user2.id in user_ids
      refute user3.id in user_ids

      # Results should be sorted by distance
      assert length(results) == 2
      assert hd(results).distance_km <= List.last(results).distance_km
    end

    test "returns empty list when no users in radius" do
      user = user_fixture()
      {:ok, _} = Locations.update_user_location(user.id, 40.7128, -74.0060)

      # Search in a different area
      results = Locations.find_users_within_radius(34.0522, -118.2437, 1.0)
      assert results == []
    end
  end

  describe "calculate_distance/4" do
    test "calculates distance between New York and Los Angeles" do
      # Approximate distance between NYC and LA is ~3944 km
      distance = Locations.calculate_distance(40.7128, -74.0060, 34.0522, -118.2437)
      assert distance > 3900 and distance < 4000
    end

    test "calculates distance between close points" do
      # Distance between two close points in NYC
      distance = Locations.calculate_distance(40.7128, -74.0060, 40.7200, -74.0100)
      assert distance < 1.0  # Should be less than 1 km
    end

    test "returns zero for identical coordinates" do
      distance = Locations.calculate_distance(40.7128, -74.0060, 40.7128, -74.0060)
      assert distance < 0.001  # Essentially zero (floating point precision)
    end
  end

  describe "cleanup_old_locations/1" do
    test "deletes locations older than specified days" do
      user = user_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      old_date = DateTime.add(now, -31 * 24 * 3600, :second)  # 31 days ago
      recent_date = DateTime.add(now, -10 * 24 * 3600, :second)  # 10 days ago

      # Create old and recent locations
      {:ok, old_location} = Locations.create_location(%{
        user_id: user.id,
        latitude: Decimal.new("40.0"),
        longitude: Decimal.new("-74.0"),
        recorded_at: old_date
      })

      {:ok, recent_location} = Locations.create_location(%{
        user_id: user.id,
        latitude: Decimal.new("41.0"),
        longitude: Decimal.new("-75.0"),
        recorded_at: recent_date
      })

      # Cleanup locations older than 30 days
      {deleted_count, _} = Locations.cleanup_old_locations(30)
      assert deleted_count == 1

      # Verify old location is gone, recent location remains
      assert is_nil(Repo.get(Location, old_location.id))
      assert Repo.get(Location, recent_location.id)
    end
  end

  describe "list_user_locations/1" do
    test "returns all locations for a user ordered by recorded_at desc" do
      user = user_fixture()

      # Create locations with explicit timestamps to ensure ordering
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      earlier = DateTime.add(now, -60, :second)

      {:ok, location1} = Locations.create_location(%{
        user_id: user.id,
        latitude: Decimal.new("40.0"),
        longitude: Decimal.new("-74.0"),
        recorded_at: earlier
      })

      {:ok, location2} = Locations.create_location(%{
        user_id: user.id,
        latitude: Decimal.new("41.0"),
        longitude: Decimal.new("-75.0"),
        recorded_at: now
      })

      locations = Locations.list_user_locations(user.id)
      assert length(locations) == 2
      assert hd(locations).id == location2.id  # Most recent first
      assert List.last(locations).id == location1.id
    end
  end

  describe "delete_user_locations/1" do
    test "deletes all locations for a user" do
      user1 = user_fixture()
      user2 = user_fixture()

      {:ok, _} = Locations.update_user_location(user1.id, 40.0, -74.0)
      {:ok, _} = Locations.update_user_location(user1.id, 41.0, -75.0)
      {:ok, user2_location} = Locations.update_user_location(user2.id, 42.0, -76.0)

      {deleted_count, _} = Locations.delete_user_locations(user1.id)
      assert deleted_count == 2

      # Verify user1's locations are gone, user2's remain
      assert Locations.list_user_locations(user1.id) == []
      assert length(Locations.list_user_locations(user2.id)) == 1
      assert Repo.get(Location, user2_location.id)
    end
  end
end
