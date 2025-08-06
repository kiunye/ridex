defmodule Ridex.RidersTest do
  use Ridex.DataCase

  alias Ridex.Riders
  alias Ridex.Riders.Rider

  import Ridex.RidersFixtures
  import Ridex.AccountsFixtures

  describe "riders" do
    test "list_riders/0 returns all riders" do
      rider = rider_fixture()
      riders = Riders.list_riders()
      assert length(riders) == 1
      assert hd(riders).id == rider.id
    end

    test "get_rider!/1 returns the rider with given id" do
      rider = rider_fixture()
      found_rider = Riders.get_rider!(rider.id)
      assert found_rider.id == rider.id
      assert found_rider.user_id == rider.user_id
    end

    test "get_rider/1 returns the rider with given id" do
      rider = rider_fixture()
      found_rider = Riders.get_rider(rider.id)
      assert found_rider.id == rider.id
      assert found_rider.user_id == rider.user_id
    end

    test "get_rider/1 returns nil for non-existent id" do
      assert Riders.get_rider(Ecto.UUID.generate()) == nil
    end

    test "get_rider_by_user_id/1 returns the rider for given user_id" do
      rider = rider_fixture()
      found_rider = Riders.get_rider_by_user_id(rider.user_id)
      assert found_rider.id == rider.id
      assert found_rider.user_id == rider.user_id
    end

    test "get_rider_by_user_id/1 returns nil for non-existent user_id" do
      assert Riders.get_rider_by_user_id(Ecto.UUID.generate()) == nil
    end

    test "create_rider/1 with valid data creates a rider" do
      user = user_fixture(%{role: :rider})
      valid_attrs = valid_rider_attributes(%{user_id: user.id})

      assert {:ok, %Rider{} = rider} = Riders.create_rider(valid_attrs)
      assert rider.user_id == user.id
      assert rider.default_pickup_location == nil
    end

    test "create_rider/1 with valid data and location creates a rider" do
      user = user_fixture(%{role: :rider})
      location = %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}
      valid_attrs = valid_rider_attributes(%{
        user_id: user.id,
        default_pickup_location: location
      })

      assert {:ok, %Rider{} = rider} = Riders.create_rider(valid_attrs)
      assert rider.user_id == user.id
      assert %Geo.Point{coordinates: {-74.0060, 40.7128}} = rider.default_pickup_location
    end

    test "create_rider/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Riders.create_rider(%{})
    end

    test "create_rider/1 with invalid location returns error changeset" do
      user = user_fixture(%{role: :rider})
      invalid_attrs = %{
        user_id: user.id,
        default_pickup_location: %Geo.Point{coordinates: {200, 100}, srid: 4326}
      }

      assert {:error, %Ecto.Changeset{} = changeset} = Riders.create_rider(invalid_attrs)
      assert "invalid coordinates" in errors_on(changeset).default_pickup_location
    end

    test "create_rider/1 enforces unique user_id constraint" do
      user = user_fixture(%{role: :rider})
      rider_fixture(%{user: user})

      assert {:error, %Ecto.Changeset{} = changeset} =
        Riders.create_rider(valid_rider_attributes(%{user_id: user.id}))

      assert "has already been taken" in errors_on(changeset).user_id
    end

    test "update_rider/2 with valid data updates the rider" do
      rider = rider_fixture()
      location = %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}
      update_attrs = %{default_pickup_location: location}

      assert {:ok, %Rider{} = updated_rider} = Riders.update_rider(rider, update_attrs)
      assert %Geo.Point{coordinates: {-74.0060, 40.7128}} = updated_rider.default_pickup_location
    end

    test "update_rider/2 with invalid data returns error changeset" do
      rider = rider_fixture()
      invalid_attrs = %{default_pickup_location: %Geo.Point{coordinates: {200, 100}, srid: 4326}}

      assert {:error, %Ecto.Changeset{}} = Riders.update_rider(rider, invalid_attrs)

      # Verify rider wasn't changed
      unchanged_rider = Riders.get_rider!(rider.id)
      assert unchanged_rider.default_pickup_location == rider.default_pickup_location
    end

    test "delete_rider/1 deletes the rider" do
      rider = rider_fixture()
      assert {:ok, %Rider{}} = Riders.delete_rider(rider)
      assert_raise Ecto.NoResultsError, fn -> Riders.get_rider!(rider.id) end
    end

    test "change_rider/1 returns a rider changeset" do
      rider = rider_fixture()
      assert %Ecto.Changeset{} = Riders.change_rider(rider)
    end
  end

  describe "rider location management" do
    test "update_rider_pickup_location/2 with valid coordinates updates location" do
      rider = rider_fixture()
      latitude = 40.7128
      longitude = -74.0060

      assert {:ok, %Rider{} = updated_rider} =
        Riders.update_rider_pickup_location(rider, %{latitude: latitude, longitude: longitude})

      assert %Geo.Point{coordinates: {^longitude, ^latitude}} = updated_rider.default_pickup_location
    end

    test "update_rider_pickup_location/2 with invalid coordinates returns error" do
      rider = rider_fixture()

      assert {:error, %Ecto.Changeset{} = changeset} =
        Riders.update_rider_pickup_location(rider, %{latitude: 200, longitude: -74.0060})

      assert "invalid coordinates" in errors_on(changeset).default_pickup_location
    end
  end
end
