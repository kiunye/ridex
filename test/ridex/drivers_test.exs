defmodule Ridex.DriversTest do
  use Ridex.DataCase

  alias Ridex.Drivers
  alias Ridex.Drivers.Driver

  import Ridex.DriversFixtures
  import Ridex.AccountsFixtures

  describe "drivers" do
    test "list_drivers/0 returns all drivers" do
      driver = driver_fixture()
      drivers = Drivers.list_drivers()
      assert length(drivers) == 1
      assert hd(drivers).id == driver.id
    end

    test "get_driver!/1 returns the driver with given id" do
      driver = driver_fixture()
      found_driver = Drivers.get_driver!(driver.id)
      assert found_driver.id == driver.id
      assert found_driver.user_id == driver.user_id
    end

    test "get_driver/1 returns the driver with given id" do
      driver = driver_fixture()
      found_driver = Drivers.get_driver(driver.id)
      assert found_driver.id == driver.id
      assert found_driver.user_id == driver.user_id
    end

    test "get_driver/1 returns nil for non-existent id" do
      assert Drivers.get_driver(Ecto.UUID.generate()) == nil
    end

    test "get_driver_by_user_id/1 returns the driver for given user_id" do
      driver = driver_fixture()
      found_driver = Drivers.get_driver_by_user_id(driver.user_id)
      assert found_driver.id == driver.id
      assert found_driver.user_id == driver.user_id
    end

    test "get_driver_by_user_id/1 returns nil for non-existent user_id" do
      assert Drivers.get_driver_by_user_id(Ecto.UUID.generate()) == nil
    end

    test "create_driver/1 with valid data creates a driver" do
      user = user_fixture(%{role: :driver})
      valid_attrs = valid_driver_attributes(%{user_id: user.id})

      assert {:ok, %Driver{} = driver} = Drivers.create_driver(valid_attrs)
      assert driver.user_id == user.id
      assert driver.vehicle_info == valid_attrs.vehicle_info
      assert driver.license_plate == String.upcase(valid_attrs.license_plate)
      assert driver.is_active == false
      assert driver.availability_status == :offline
    end

    test "create_driver/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Drivers.create_driver(%{})
    end

    test "create_driver/1 with invalid vehicle_info returns error changeset" do
      user = user_fixture(%{role: :driver})
      invalid_attrs = %{
        user_id: user.id,
        vehicle_info: %{"make" => "Toyota"} # Missing model and year
      }

      assert {:error, %Ecto.Changeset{} = changeset} = Drivers.create_driver(invalid_attrs)
      assert "must include model, year" in errors_on(changeset).vehicle_info
    end

    test "create_driver/1 with invalid license_plate returns error changeset" do
      user = user_fixture(%{role: :driver})
      invalid_attrs = valid_driver_attributes(%{
        user_id: user.id,
        license_plate: "TOOLONGPLATE123"
      })

      assert {:error, %Ecto.Changeset{} = changeset} = Drivers.create_driver(invalid_attrs)
      assert "must be 2-10 characters, letters, numbers, hyphens, and spaces only" in errors_on(changeset).license_plate
    end

    test "create_driver/1 enforces unique user_id constraint" do
      user = user_fixture(%{role: :driver})
      driver_fixture(%{user: user})

      assert {:error, %Ecto.Changeset{} = changeset} =
        Drivers.create_driver(valid_driver_attributes(%{user_id: user.id}))

      assert "has already been taken" in errors_on(changeset).user_id
    end

    test "create_driver/1 enforces unique license_plate constraint" do
      license_plate = "ABC123"
      driver_fixture(%{license_plate: license_plate})

      user = user_fixture(%{role: :driver})
      assert {:error, %Ecto.Changeset{} = changeset} =
        Drivers.create_driver(valid_driver_attributes(%{
          user_id: user.id,
          license_plate: license_plate
        }))

      assert "has already been taken" in errors_on(changeset).license_plate
    end

    test "update_driver/2 with valid data updates the driver" do
      driver = driver_fixture()
      update_attrs = %{
        vehicle_info: %{"make" => "Honda", "model" => "Civic", "year" => 2021},
        license_plate: "XYZ789"
      }

      assert {:ok, %Driver{} = driver} = Drivers.update_driver(driver, update_attrs)
      assert driver.vehicle_info == update_attrs.vehicle_info
      assert driver.license_plate == "XYZ789"
    end

    test "update_driver/2 with invalid data returns error changeset" do
      driver = driver_fixture()
      invalid_attrs = %{vehicle_info: %{"make" => ""}}

      assert {:error, %Ecto.Changeset{}} = Drivers.update_driver(driver, invalid_attrs)

      # Verify driver wasn't changed
      unchanged_driver = Drivers.get_driver!(driver.id)
      assert unchanged_driver.vehicle_info == driver.vehicle_info
    end

    test "delete_driver/1 deletes the driver" do
      driver = driver_fixture()
      assert {:ok, %Driver{}} = Drivers.delete_driver(driver)
      assert_raise Ecto.NoResultsError, fn -> Drivers.get_driver!(driver.id) end
    end

    test "change_driver/1 returns a driver changeset" do
      driver = driver_fixture()
      assert %Ecto.Changeset{} = Drivers.change_driver(driver)
    end
  end

  describe "driver location management" do
    test "update_driver_location/2 with valid coordinates updates location" do
      driver = driver_fixture()
      latitude = 40.7128
      longitude = -74.0060

      assert {:ok, %Driver{} = updated_driver} =
        Drivers.update_driver_location(driver, %{latitude: latitude, longitude: longitude})

      assert %Geo.Point{coordinates: {^longitude, ^latitude}} = updated_driver.current_location
    end

    test "update_driver_location/2 with invalid coordinates returns error" do
      driver = driver_fixture()

      assert {:error, %Ecto.Changeset{} = changeset} =
        Drivers.update_driver_location(driver, %{latitude: 200, longitude: -74.0060})

      assert "invalid coordinates" in errors_on(changeset).current_location
    end
  end

  describe "driver availability management" do
    test "set_driver_availability/2 with valid status updates availability" do
      driver = active_driver_fixture()

      assert {:ok, %Driver{} = updated_driver} =
        Drivers.set_driver_availability(driver, :away)

      assert updated_driver.availability_status == :away
    end

    test "set_driver_availability/2 with invalid status returns error" do
      driver = driver_fixture()

      assert {:error, %Ecto.Changeset{} = changeset} =
        Drivers.set_driver_availability(driver, :invalid_status)

      assert "is invalid" in errors_on(changeset).availability_status
    end

    test "activate_driver/1 sets driver to active" do
      driver = driver_fixture()

      assert {:ok, %Driver{} = updated_driver} = Drivers.activate_driver(driver)

      assert updated_driver.is_active == true
      assert updated_driver.availability_status == :active
    end

    test "deactivate_driver/1 sets driver to offline" do
      driver = active_driver_fixture()

      assert {:ok, %Driver{} = updated_driver} = Drivers.deactivate_driver(driver)

      assert updated_driver.is_active == false
      assert updated_driver.availability_status == :offline
    end
  end

  describe "driver queries" do
    test "list_active_drivers/0 returns only active drivers" do
      active_driver = active_driver_fixture()
      _inactive_driver = driver_fixture()

      active_drivers = Drivers.list_active_drivers()

      assert length(active_drivers) == 1
      assert hd(active_drivers).id == active_driver.id
    end

    test "get_nearby_active_drivers/3 returns drivers within radius" do
      # Create drivers at different locations
      nearby_driver = driver_with_location_fixture(40.7128, -74.0060, %{
        is_active: true,
        availability_status: :active
      })

      far_driver = driver_with_location_fixture(41.8781, -87.6298, %{
        is_active: true,
        availability_status: :active
      })

      _inactive_nearby = driver_with_location_fixture(40.7130, -74.0062)

      # Search within 10km of nearby_driver location (should only find nearby_driver)
      nearby_drivers = Drivers.get_nearby_active_drivers(40.7128, -74.0060, 10.0)

      assert length(nearby_drivers) == 1
      assert hd(nearby_drivers).id == nearby_driver.id
      refute Enum.any?(nearby_drivers, &(&1.id == far_driver.id))
    end

    test "get_nearby_active_drivers/3 returns empty list when no drivers nearby" do
      _far_driver = driver_with_location_fixture(41.8781, -87.6298, %{
        is_active: true,
        availability_status: :active
      })

      # Search in a different location with small radius
      nearby_drivers = Drivers.get_nearby_active_drivers(40.7128, -74.0060, 0.1)

      assert nearby_drivers == []
    end

    test "get_nearby_active_drivers/3 orders drivers by distance" do
      # Create drivers at different distances from search point
      closer_driver = driver_with_location_fixture(40.7130, -74.0062, %{
        is_active: true,
        availability_status: :active
      })

      farther_driver = driver_with_location_fixture(40.7140, -74.0070, %{
        is_active: true,
        availability_status: :active
      })

      # Search from a point closer to closer_driver
      nearby_drivers = Drivers.get_nearby_active_drivers(40.7128, -74.0060, 5.0)

      assert length(nearby_drivers) == 2
      assert hd(nearby_drivers).id == closer_driver.id
      assert List.last(nearby_drivers).id == farther_driver.id
    end
  end
end
