defmodule Ridex.LocationServiceTest do
  use Ridex.DataCase

  alias Ridex.LocationService
  alias Ridex.Locations
  alias Ridex.Drivers

  import Ridex.AccountsFixtures

  describe "start_location_tracking/4" do
    test "creates location and updates driver location if user is a driver" do
      driver_user = user_fixture(%{role: "driver"})
      {:ok, driver} = Drivers.create_driver(%{
        user_id: driver_user.id,
        vehicle_info: %{"make" => "Toyota", "model" => "Camry", "year" => 2020},
        license_plate: "ABC123"
      })

      assert {:ok, location} = LocationService.start_location_tracking(driver_user.id, 40.7128, -74.0060, 10.5)

      # Check location was created
      assert location.user_id == driver_user.id
      assert Decimal.equal?(location.latitude, Decimal.new("40.7128"))
      assert Decimal.equal?(location.longitude, Decimal.new("-74.0060"))

      # Check driver location was updated
      updated_driver = Drivers.get_driver!(driver.id)
      assert updated_driver.current_location
      assert updated_driver.current_location.coordinates == {-74.0060, 40.7128}
    end

    test "creates location for rider without updating driver table" do
      rider_user = user_fixture(%{role: "rider"})

      assert {:ok, location} = LocationService.start_location_tracking(rider_user.id, 40.7128, -74.0060, 10.5)

      # Check location was created
      assert location.user_id == rider_user.id
      assert Decimal.equal?(location.latitude, Decimal.new("40.7128"))
      assert Decimal.equal?(location.longitude, Decimal.new("-74.0060"))
    end

    test "returns error for invalid coordinates" do
      user = user_fixture()

      assert {:error, changeset} = LocationService.start_location_tracking(user.id, 91.0, -74.0060)
      assert %{latitude: ["must be between -90 and 90 degrees"]} = errors_on(changeset)
    end
  end

  describe "stop_location_tracking/1" do
    test "clears driver location if user is a driver" do
      driver_user = user_fixture(%{role: "driver"})
      {:ok, driver} = Drivers.create_driver(%{
        user_id: driver_user.id,
        vehicle_info: %{"make" => "Toyota", "model" => "Camry", "year" => 2020},
        license_plate: "ABC123"
      })

      # Start tracking first
      {:ok, _} = LocationService.start_location_tracking(driver_user.id, 40.7128, -74.0060)

      # Verify driver location is set
      driver_with_location = Drivers.get_driver!(driver.id)
      assert driver_with_location.current_location

      # Stop tracking
      assert :ok = LocationService.stop_location_tracking(driver_user.id)

      # Verify driver location is cleared
      updated_driver = Drivers.get_driver!(driver.id)
      assert is_nil(updated_driver.current_location)
    end

    test "returns ok for rider" do
      rider_user = user_fixture(%{role: "rider"})
      assert :ok = LocationService.stop_location_tracking(rider_user.id)
    end
  end

  describe "update_location/4" do
    test "updates location and driver location for driver" do
      driver_user = user_fixture(%{role: "driver"})
      {:ok, driver} = Drivers.create_driver(%{
        user_id: driver_user.id,
        vehicle_info: %{"make" => "Toyota", "model" => "Camry", "year" => 2020},
        license_plate: "ABC123"
      })

      assert {:ok, location} = LocationService.update_location(driver_user.id, 40.7128, -74.0060, 15.0)

      # Check location was created
      assert location.user_id == driver_user.id
      assert Decimal.equal?(location.accuracy, Decimal.new("15.0"))

      # Check driver location was updated
      updated_driver = Drivers.get_driver!(driver.id)
      assert updated_driver.current_location.coordinates == {-74.0060, 40.7128}
    end
  end

  describe "get_current_location/1" do
    test "returns latest location for user" do
      user = user_fixture()

      # Create locations with explicit timestamps
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      earlier = DateTime.add(now, -60, :second)

      {:ok, _} = Locations.create_location(%{
        user_id: user.id,
        latitude: Decimal.new("40.0"),
        longitude: Decimal.new("-74.0"),
        recorded_at: earlier
      })

      {:ok, latest} = Locations.create_location(%{
        user_id: user.id,
        latitude: Decimal.new("41.0"),
        longitude: Decimal.new("-75.0"),
        recorded_at: now
      })

      current = LocationService.get_current_location(user.id)
      assert current.id == latest.id
    end

    test "returns nil for user with no locations" do
      user = user_fixture()
      assert is_nil(LocationService.get_current_location(user.id))
    end
  end

  describe "get_nearby_drivers/3" do
    test "returns active drivers within radius with distance and vehicle info" do
      # Create driver users
      driver1_user = user_fixture(%{role: "driver"})
      driver2_user = user_fixture(%{role: "driver"})
      driver3_user = user_fixture(%{role: "driver"})

      # Create driver profiles
      {:ok, driver1} = Drivers.create_driver(%{
        user_id: driver1_user.id,
        vehicle_info: %{"make" => "Toyota", "model" => "Camry", "year" => 2020},
        license_plate: "ABC123",
        is_active: true,
        availability_status: :active
      })

      {:ok, driver2} = Drivers.create_driver(%{
        user_id: driver2_user.id,
        vehicle_info: %{"make" => "Honda", "model" => "Civic", "year" => 2019},
        license_plate: "XYZ789",
        is_active: true,
        availability_status: :active
      })

      {:ok, _driver3} = Drivers.create_driver(%{
        user_id: driver3_user.id,
        vehicle_info: %{"make" => "Ford", "model" => "Focus", "year" => 2018},
        license_plate: "DEF456",
        is_active: false,  # Inactive driver
        availability_status: :offline
      })

      # Set locations
      {:ok, _} = LocationService.update_location(driver1_user.id, 40.7128, -74.0060)  # NYC
      {:ok, _} = LocationService.update_location(driver2_user.id, 40.7200, -74.0100)  # Close to NYC
      {:ok, _} = LocationService.update_location(driver3_user.id, 40.7150, -74.0080)  # Close but inactive

      # Search for drivers near NYC
      nearby_drivers = LocationService.get_nearby_drivers(40.7128, -74.0060, 5.0)

      assert length(nearby_drivers) == 2  # Only active drivers

      # Check first driver (should be closest)
      first_driver = hd(nearby_drivers)
      assert first_driver.driver_id in [driver1.id, driver2.id]
      assert first_driver.latitude == 40.7128 or first_driver.latitude == 40.7200
      assert first_driver.distance_km < 5.0
      assert first_driver.vehicle_info
      assert first_driver.license_plate
      assert first_driver.last_updated

      # Results should be sorted by distance
      distances = Enum.map(nearby_drivers, & &1.distance_km)
      assert distances == Enum.sort(distances)
    end

    test "returns empty list when no active drivers in radius" do
      driver_user = user_fixture(%{role: "driver"})
      {:ok, _driver} = Drivers.create_driver(%{
        user_id: driver_user.id,
        vehicle_info: %{"make" => "Toyota", "model" => "Camry", "year" => 2020},
        license_plate: "ABC123",
        is_active: false  # Inactive
      })

      {:ok, _} = LocationService.update_location(driver_user.id, 40.7128, -74.0060)

      nearby_drivers = LocationService.get_nearby_drivers(40.7128, -74.0060, 5.0)
      assert nearby_drivers == []
    end
  end

  describe "calculate_distance/4" do
    test "calculates distance between two points" do
      # Distance between NYC and LA
      distance = LocationService.calculate_distance(40.7128, -74.0060, 34.0522, -118.2437)
      assert distance > 3900 and distance < 4000
    end

    test "returns zero for same coordinates" do
      distance = LocationService.calculate_distance(40.7128, -74.0060, 40.7128, -74.0060)
      assert distance < 0.001
    end
  end

  describe "is_location_accurate?/2" do
    test "returns true for accurate locations" do
      assert LocationService.is_location_accurate?(50.0, 100.0)
      assert LocationService.is_location_accurate?(10.0)  # Default max is 100
    end

    test "returns false for inaccurate locations" do
      refute LocationService.is_location_accurate?(150.0, 100.0)
      refute LocationService.is_location_accurate?(200.0)  # Default max is 100
    end

    test "returns true for nil accuracy" do
      assert LocationService.is_location_accurate?(nil)
    end

    test "returns false for invalid accuracy values" do
      refute LocationService.is_location_accurate?("invalid")
      refute LocationService.is_location_accurate?(%{})
    end
  end

  describe "get_location_history/2" do
    test "returns location history for specified hours" do
      user = user_fixture()

      # Create locations at different times
      {:ok, _} = LocationService.update_location(user.id, 40.0, -74.0)
      Process.sleep(10)
      {:ok, _} = LocationService.update_location(user.id, 41.0, -75.0)

      history = LocationService.get_location_history(user.id, 1)  # Last 1 hour
      assert length(history) == 2
    end

    test "returns empty list for user with no locations" do
      user = user_fixture()
      history = LocationService.get_location_history(user.id)
      assert history == []
    end
  end

  describe "broadcast_location_update/2" do
    test "returns ok with location (placeholder implementation)" do
      user = user_fixture()
      {:ok, location} = LocationService.update_location(user.id, 40.7128, -74.0060)

      assert {:ok, returned_location} = LocationService.broadcast_location_update(user.id, location)
      assert returned_location.id == location.id
    end
  end
end
