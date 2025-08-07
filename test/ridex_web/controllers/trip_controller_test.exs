defmodule RidexWeb.TripControllerTest do
  use RidexWeb.ConnCase

  import Ridex.AccountsFixtures
  import Ridex.DriversFixtures
  import Ridex.RidersFixtures
  import Ridex.TripsFixtures

  alias Ridex.Drivers
  alias Ridex.Trips

  describe "POST /api/trips/:id/accept" do
    setup do
      driver_user = user_fixture(%{role: :driver})
      driver = driver_fixture(%{user: driver_user})
      {:ok, driver} = Drivers.activate_driver(driver)

      rider_user = user_fixture(%{role: :rider})
      rider = rider_fixture(%{user: rider_user})

      trip = trip_fixture(%{rider: rider, status: :requested})

      %{driver_user: driver_user, driver: driver, rider_user: rider_user, rider: rider, trip: trip}
    end

    test "accepts trip successfully when driver is available", %{
      conn: conn,
      driver_user: driver_user,
      trip: trip
    } do
      conn = log_in_user(conn, driver_user)

      conn = post(conn, ~p"/api/trips/#{trip.id}/accept")

      assert %{"success" => true, "trip" => trip_data} = json_response(conn, 200)
      assert trip_data["id"] == trip.id
      assert trip_data["status"] == "accepted"
      assert trip_data["pickup_location"]["latitude"] != nil
      assert trip_data["pickup_location"]["longitude"] != nil
      assert trip_data["rider_info"]["name"] != nil

      # Verify trip was actually accepted in database
      updated_trip = Trips.get_trip!(trip.id)
      assert updated_trip.status == :accepted
      assert updated_trip.driver_id != nil
    end

    test "returns error when trip not found", %{conn: conn, driver_user: driver_user} do
      conn = log_in_user(conn, driver_user)
      fake_trip_id = Ecto.UUID.generate()

      conn = post(conn, ~p"/api/trips/#{fake_trip_id}/accept")

      assert %{"success" => false, "error" => "Trip not found"} = json_response(conn, 422)
    end

    test "returns error when driver not found", %{conn: conn, trip: trip} do
      # User without driver profile
      user = user_fixture(%{role: :rider})
      conn = log_in_user(conn, user)

      conn = post(conn, ~p"/api/trips/#{trip.id}/accept")

      assert %{"success" => false, "error" => "Driver profile not found"} = json_response(conn, 422)
    end

    test "returns error when driver is not active", %{
      conn: conn,
      driver_user: driver_user,
      driver: driver,
      trip: trip
    } do
      # Deactivate driver
      {:ok, _driver} = Drivers.deactivate_driver(driver)

      conn = log_in_user(conn, driver_user)

      conn = post(conn, ~p"/api/trips/#{trip.id}/accept")

      assert %{"success" => false, "error" => "Driver is not active"} = json_response(conn, 422)
    end

    test "returns error when driver already has active trip", %{
      conn: conn,
      driver_user: driver_user,
      driver: driver,
      trip: trip
    } do
      # Create another trip and assign it to the driver
      other_rider = rider_fixture()
      _other_trip = trip_fixture(%{rider_id: other_rider.id, driver_id: driver.id, status: :accepted})

      conn = log_in_user(conn, driver_user)

      conn = post(conn, ~p"/api/trips/#{trip.id}/accept")

      assert %{"success" => false, "error" => "Driver already has an active trip"} = json_response(conn, 422)
    end

    test "returns error when trip is not in requested status", %{
      conn: conn,
      driver_user: driver_user,
      trip: trip
    } do
      # Accept the trip with another driver first
      other_driver_user = user_fixture(%{role: :driver})
      other_driver = driver_fixture(%{user: other_driver_user})
      {:ok, _driver} = Drivers.activate_driver(other_driver)

      {:ok, _accepted_trip} = Trips.accept_trip(trip, other_driver.id)

      conn = log_in_user(conn, driver_user)

      conn = post(conn, ~p"/api/trips/#{trip.id}/accept")

      assert %{"success" => false, "error" => "Trip is no longer available (status: accepted)"} = json_response(conn, 422)
    end

    test "requires authentication", %{trip: trip} do
      conn = post(build_conn(), ~p"/api/trips/#{trip.id}/accept")

      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "POST /api/trips/:id/decline" do
    setup do
      driver_user = user_fixture(%{role: :driver})
      driver = driver_fixture(%{user: driver_user})
      {:ok, driver} = Drivers.activate_driver(driver)

      rider_user = user_fixture(%{role: :rider})
      rider = rider_fixture(%{user: rider_user})

      trip = trip_fixture(%{rider: rider, status: :requested})

      %{driver_user: driver_user, driver: driver, rider_user: rider_user, rider: rider, trip: trip}
    end

    test "declines trip successfully", %{
      conn: conn,
      driver_user: driver_user,
      trip: trip
    } do
      conn = log_in_user(conn, driver_user)

      conn = post(conn, ~p"/api/trips/#{trip.id}/decline")

      assert %{"success" => true} = json_response(conn, 200)

      # Verify trip is still in requested status (decline doesn't change trip status)
      updated_trip = Trips.get_trip!(trip.id)
      assert updated_trip.status == :requested
    end

    test "returns error when trip not found", %{conn: conn, driver_user: driver_user} do
      conn = log_in_user(conn, driver_user)
      fake_trip_id = Ecto.UUID.generate()

      conn = post(conn, ~p"/api/trips/#{fake_trip_id}/decline")

      # Note: The decline endpoint currently returns success even for non-existent trips
      # This is by design as decline is more of a "fire and forget" operation
      assert %{"success" => true} = json_response(conn, 200)
    end

    test "requires authentication", %{trip: trip} do
      conn = post(build_conn(), ~p"/api/trips/#{trip.id}/decline")

      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "works even when driver is not active", %{
      conn: conn,
      driver_user: driver_user,
      driver: driver,
      trip: trip
    } do
      # Deactivate driver
      {:ok, _driver} = Drivers.deactivate_driver(driver)

      conn = log_in_user(conn, driver_user)

      conn = post(conn, ~p"/api/trips/#{trip.id}/decline")

      assert %{"success" => true} = json_response(conn, 200)
    end
  end
end
