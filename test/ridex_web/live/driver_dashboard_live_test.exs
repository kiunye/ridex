defmodule RidexWeb.DriverDashboardLiveTest do
  use RidexWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ridex.AccountsFixtures
  import Ridex.DriversFixtures

  alias Ridex.Drivers

  describe "Driver Dashboard" do
    setup do
      user = user_fixture(%{role: :driver})
      driver = driver_fixture(%{user: user})
      %{user: user, driver: driver}
    end

    test "redirects non-drivers to home page", %{conn: conn} do
      rider_user = user_fixture(%{role: :rider})
      conn = log_in_user(conn, rider_user)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/driver/dashboard")
    end

    test "displays driver dashboard for authenticated driver", %{conn: conn, user: user, driver: _driver} do
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/driver/dashboard")

      assert html =~ "Driver Dashboard"
      assert html =~ "Welcome back, #{user.name}"
      assert html =~ "Current Status"
      assert html =~ "Offline"  # Default status
    end

    test "displays vehicle information when available", %{conn: conn, user: user, driver: driver} do
      {:ok, _updated_driver} = Drivers.update_driver(driver, %{
        vehicle_info: %{"make" => "Toyota", "model" => "Camry", "year" => 2020},
        license_plate: "ABC123"
      })

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/driver/dashboard")

      assert html =~ "Toyota Camry"
      assert html =~ "ABC123"
    end

    test "shows location permission request initially", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/driver/dashboard")

      assert html =~ "Location permission not requested"
      assert html =~ "Enable Location"
    end

    test "allows driver to set up vehicle information", %{conn: conn, user: user, driver: driver} do
      # Create a driver without vehicle info
      {:ok, driver_without_vehicle} = Drivers.update_driver(driver, %{
        vehicle_info: nil,
        license_plate: nil
      })

      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/driver/dashboard")

      # Initially shows "Not set" for vehicle
      assert html =~ "Not set"
      assert html =~ "Set Up"

      # Click to show vehicle form
      html = view |> element("button", "Set Up") |> render_click()
      assert html =~ "Vehicle Information"
      assert html =~ "Make"
      assert html =~ "Model"

      # Fill out and submit the form
      view
      |> form("form", driver: %{
        vehicle_info: %{make: "Honda", model: "Civic", year: "2021", color: "Blue"},
        license_plate: "XYZ789"
      })
      |> render_submit()

      # Verify the vehicle information is updated
      updated_driver = Drivers.get_driver!(driver.id)
      assert updated_driver.vehicle_info["make"] == "Honda"
      assert updated_driver.vehicle_info["model"] == "Civic"
      assert updated_driver.license_plate == "XYZ789"
    end

    test "validates vehicle information form", %{conn: conn, user: user, driver: driver} do
      # Create a driver without vehicle info
      {:ok, _driver_without_vehicle} = Drivers.update_driver(driver, %{
        vehicle_info: nil,
        license_plate: nil
      })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Show vehicle form
      view |> element("button", "Set Up") |> render_click()

      # Submit form with invalid data
      html = view
      |> form("form", driver: %{
        vehicle_info: %{make: "", model: "Civic", year: "1980"},  # Invalid year and empty make
        license_plate: ""
      })
      |> render_submit()

      # Should show validation errors
      assert html =~ "must include make"
    end

    test "handles location permission granted", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Simulate location received
      view
      |> element("button", "Enable Location")
      |> render_click()

      # Simulate JavaScript location response
      render_hook(view, "location_received", %{
        "latitude" => 40.7128,
        "longitude" => -74.0060,
        "accuracy" => 10.0
      })

      html = render(view)
      assert html =~ "Location Active"
      assert html =~ "Lat: 40.712800"
      assert html =~ "Lng: -74.006000"
      assert html =~ "Accuracy: 10m"
    end

    test "handles location permission denied", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Simulate location error
      render_hook(view, "location_error", %{"error" => "permission_denied"})

      html = render(view)
      assert html =~ "Location Access Required"
      assert html =~ "Location permission denied"
    end

    test "enables check-in button when location is available", %{conn: conn, user: user, driver: _driver} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Provide location
      render_hook(view, "location_received", %{
        "latitude" => 40.7128,
        "longitude" => -74.0060,
        "accuracy" => 10.0
      })

      html = render(view)
      assert html =~ "Check In"
      refute html =~ "Check Out"
    end

    test "shows check-out button when driver is active", %{conn: conn, user: user, driver: driver} do
      # Activate the driver first
      {:ok, _driver} = Drivers.activate_driver(driver)

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/driver/dashboard")

      assert html =~ "Active - Available for rides"
      assert html =~ "Check Out"
      refute html =~ "Check In"
    end

    test "handles successful check-in", %{conn: conn, user: user, driver: _driver} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Provide location
      render_hook(view, "location_received", %{
        "latitude" => 40.7128,
        "longitude" => -74.0060,
        "accuracy" => 10.0
      })

      # Simulate successful check-in response
      render_hook(view, "checkin_success", %{})

      # Verify flash message
      assert render(view) =~ "Successfully checked in"
    end

    test "handles check-in error", %{conn: conn, user: user, driver: _driver} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Simulate check-in error
      render_hook(view, "checkin_error", %{
        "errors" => %{"availability_status" => ["invalid status"]}
      })

      html = render(view)
      assert html =~ "Check-in failed"
      assert html =~ "availability_status: invalid status"
    end

    test "handles successful check-out", %{conn: conn, user: user, driver: driver} do
      # Start with active driver
      {:ok, _driver} = Drivers.activate_driver(driver)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Simulate successful check-out response
      render_hook(view, "checkout_success", %{})

      html = render(view)
      assert html =~ "Successfully checked out"
    end

    test "handles check-out error", %{conn: conn, user: user, driver: driver} do
      # Start with active driver
      {:ok, _driver} = Drivers.activate_driver(driver)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Simulate check-out error
      render_hook(view, "checkout_error", %{
        "errors" => %{"availability_status" => ["cannot change status"]}
      })

      html = render(view)
      assert html =~ "Check-out failed"
      assert html =~ "availability_status: cannot change status"
    end

    test "displays loading state during check-in", %{conn: conn, user: user, driver: _driver} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Provide location
      render_hook(view, "location_received", %{
        "latitude" => 40.7128,
        "longitude" => -74.0060,
        "accuracy" => 10.0
      })

      # Click check-in button
      view
      |> element("button", "Check In")
      |> render_click()

      html = render(view)
      assert html =~ "Checking In..."
    end

    test "displays loading state during check-out", %{conn: conn, user: user, driver: driver} do
      # Start with active driver
      {:ok, _driver} = Drivers.activate_driver(driver)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Click check-out button
      view
      |> element("button", "Check Out")
      |> render_click()

      html = render(view)
      assert html =~ "Checking Out..."
    end

    test "shows appropriate status colors and text", %{conn: conn, user: user, driver: driver} do
      conn = log_in_user(conn, user)

      # Test offline status
      {:ok, view, html} = live(conn, ~p"/driver/dashboard")
      assert html =~ "bg-gray-100 text-gray-800"
      assert html =~ "Offline"

      # Test active status
      {:ok, _driver} = Drivers.activate_driver(driver)
      send(view.pid, %{event: "driver_status_changed", payload: %{user_id: user.id, status: "active"}})

      html = render(view)
      assert html =~ "bg-green-100 text-green-800"
      assert html =~ "Active - Available for rides"
    end

    test "shows warning when location is required for check-in", %{conn: conn, user: user, driver: _driver} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/driver/dashboard")

      assert html =~ "Enable location services to check in"
    end

    test "displays quick stats placeholders", %{conn: conn, user: user, driver: _driver} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/driver/dashboard")

      assert html =~ "Today&#39;s Trips"
      assert html =~ "Hours Online"
      assert html =~ "Earnings"
      assert html =~ "$0.00"
    end
  end

  describe "Real-time updates" do
    setup do
      user = user_fixture(%{role: :driver})
      driver = driver_fixture(%{user: user})
      %{user: user, driver: driver}
    end

    test "updates location when location_updated message received", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # First set location permission to granted
      render_hook(view, "location_received", %{
        "latitude" => 40.7128,
        "longitude" => -74.0060,
        "accuracy" => 10.0
      })

      # Send location update message
      send(view.pid, %{
        event: "location_updated",
        payload: %{
          user_id: user.id,
          latitude: 40.7589,
          longitude: -73.9851,
          accuracy: 15.0
        }
      })

      html = render(view)
      assert html =~ "Lat: 40.758900"
      assert html =~ "Lng: -73.985100"
      assert html =~ "Accuracy: 15m"
    end

    test "ignores location updates for other users", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Send location update for different user
      other_user_id = Ecto.UUID.generate()
      send(view.pid, %{
        event: "location_updated",
        payload: %{
          user_id: other_user_id,
          latitude: 40.7589,
          longitude: -73.9851,
          accuracy: 15.0
        }
      })

      html = render(view)
      refute html =~ "Lat: 40.758900"
    end

    test "updates driver status when driver_status_changed message received", %{conn: conn, user: user, driver: driver} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Activate driver externally
      {:ok, _driver} = Drivers.activate_driver(driver)

      # Send status change message
      send(view.pid, %{
        event: "driver_status_changed",
        payload: %{
          user_id: user.id,
          status: "active"
        }
      })

      html = render(view)
      assert html =~ "Active - Available for rides"
      assert html =~ "bg-green-100 text-green-800"
    end
  end

  describe "Ride request handling" do
    setup do
      user = user_fixture(%{role: :driver})
      driver = driver_fixture(%{user: user})
      {:ok, _driver} = Drivers.activate_driver(driver)
      %{user: user, driver: driver}
    end

    test "displays ride request notification when received", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Send ride request message
      ride_request = %{
        trip_id: Ecto.UUID.generate(),
        pickup_location: %{latitude: 40.7128, longitude: -74.0060},
        distance_km: 2.5,
        estimated_arrival_minutes: 8,
        expires_at: DateTime.utc_now() |> DateTime.add(30, :second)
      }

      send(view.pid, %{event: "ride_request", payload: ride_request})

      html = render(view)
      assert html =~ "New Ride Request!"
      assert html =~ "40.7128, -74.006"
      assert html =~ "2.5 km away"
      assert html =~ "8 minutes"
      assert html =~ "Accept Ride"
      assert html =~ "Decline"
      assert html =~ "Expires in"
    end

    test "does not show ride request when driver is inactive", %{conn: conn, user: user, driver: driver} do
      # Deactivate driver
      {:ok, updated_driver} = Drivers.deactivate_driver(driver)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Update the driver state in the LiveView
      send(view.pid, {:assign, :driver, updated_driver})

      # Send ride request message
      ride_request = %{
        trip_id: Ecto.UUID.generate(),
        pickup_location: %{latitude: 40.7128, longitude: -74.0060},
        distance_km: 2.5,
        estimated_arrival_minutes: 8
      }

      send(view.pid, %{event: "ride_request", payload: ride_request})

      html = render(view)
      refute html =~ "New Ride Request!"
    end

    test "does not show ride request when driver has current trip", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Set current trip
      current_trip = %{
        "id" => Ecto.UUID.generate(),
        "status" => "accepted",
        "pickup_location" => %{latitude: 40.7128, longitude: -74.0060}
      }
      send(view.pid, {:assign, :current_trip, current_trip})

      # Send ride request message
      ride_request = %{
        trip_id: Ecto.UUID.generate(),
        pickup_location: %{latitude: 40.7128, longitude: -74.0060},
        distance_km: 2.5,
        estimated_arrival_minutes: 8
      }

      send(view.pid, %{event: "ride_request", payload: ride_request})

      html = render(view)
      refute html =~ "New Ride Request!"
    end

    test "handles ride request acceptance", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Send ride request
      ride_request = %{
        trip_id: Ecto.UUID.generate(),
        pickup_location: %{latitude: 40.7128, longitude: -74.0060},
        distance_km: 2.5,
        estimated_arrival_minutes: 8
      }

      send(view.pid, %{event: "ride_request", payload: ride_request})

      # Click accept button
      view
      |> element("button", "Accept Ride")
      |> render_click()

      html = render(view)
      assert html =~ "Accepting..."
    end

    test "handles ride request decline", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Send ride request
      ride_request = %{
        trip_id: Ecto.UUID.generate(),
        pickup_location: %{latitude: 40.7128, longitude: -74.0060},
        distance_km: 2.5,
        estimated_arrival_minutes: 8
      }

      send(view.pid, %{event: "ride_request", payload: ride_request})

      # Click decline button
      view
      |> element("button", "Decline")
      |> render_click()

      html = render(view)
      assert html =~ "Declining..."
    end

    test "handles successful trip acceptance", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Send ride request first
      ride_request = %{
        trip_id: Ecto.UUID.generate(),
        pickup_location: %{latitude: 40.7128, longitude: -74.0060},
        distance_km: 2.5,
        estimated_arrival_minutes: 8
      }

      send(view.pid, %{event: "ride_request", payload: ride_request})

      # Simulate successful acceptance
      trip_data = %{
        "id" => ride_request.trip_id,
        "status" => "accepted",
        "pickup_location" => %{latitude: 40.7128, longitude: -74.0060},
        "rider_info" => %{"name" => "John Doe"}
      }

      render_hook(view, "trip_accepted", %{"trip" => trip_data})

      html = render(view)
      assert html =~ "Trip accepted!"
      assert html =~ "Current Trip"
      assert html =~ "Trip Accepted - Navigate to Pickup"
      assert html =~ "John Doe"
      refute html =~ "New Ride Request!"
    end

    test "handles trip acceptance error", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Send ride request first
      ride_request = %{
        trip_id: Ecto.UUID.generate(),
        pickup_location: %{latitude: 40.7128, longitude: -74.0060},
        distance_km: 2.5,
        estimated_arrival_minutes: 8
      }

      send(view.pid, %{event: "ride_request", payload: ride_request})

      # Simulate acceptance error
      render_hook(view, "trip_accept_error", %{"error" => "Trip no longer available"})

      html = render(view)
      assert html =~ "Failed to accept trip: Trip no longer available"
    end

    test "handles successful trip decline", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Send ride request first
      ride_request = %{
        trip_id: Ecto.UUID.generate(),
        pickup_location: %{latitude: 40.7128, longitude: -74.0060},
        distance_km: 2.5,
        estimated_arrival_minutes: 8
      }

      send(view.pid, %{event: "ride_request", payload: ride_request})

      # Simulate successful decline
      render_hook(view, "trip_declined", %{})

      html = render(view)
      assert html =~ "Trip declined."
      refute html =~ "New Ride Request!"
    end

    test "handles ride request timeout", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Send ride request
      trip_id = Ecto.UUID.generate()
      ride_request = %{
        trip_id: trip_id,
        pickup_location: %{latitude: 40.7128, longitude: -74.0060},
        distance_km: 2.5,
        estimated_arrival_minutes: 8
      }

      send(view.pid, %{event: "ride_request", payload: ride_request})

      # Verify request is shown
      html = render(view)
      assert html =~ "New Ride Request!"

      # Send timeout message
      send(view.pid, {:ride_request_timeout, trip_id})

      html = render(view)
      assert html =~ "Ride request expired."
      refute html =~ "New Ride Request!"
    end

    test "handles ride request cancellation", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Send ride request
      ride_request = %{
        trip_id: Ecto.UUID.generate(),
        pickup_location: %{latitude: 40.7128, longitude: -74.0060},
        distance_km: 2.5,
        estimated_arrival_minutes: 8
      }

      send(view.pid, %{event: "ride_request", payload: ride_request})

      # Send cancellation message
      send(view.pid, %{event: "ride_request_cancelled", payload: %{reason: "rider_cancelled"}})

      html = render(view)
      assert html =~ "Ride request was cancelled."
      refute html =~ "New Ride Request!"
    end
  end

  describe "Trip management" do
    setup do
      user = user_fixture(%{role: :driver})
      driver = driver_fixture(%{user: user})
      {:ok, _driver} = Drivers.activate_driver(driver)
      %{user: user, driver: driver}
    end

    test "displays current trip controls when trip is accepted", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Set current trip
      trip_data = %{
        "id" => Ecto.UUID.generate(),
        "status" => "accepted",
        "pickup_location" => %{latitude: 40.7128, longitude: -74.0060},
        "rider_info" => %{"name" => "John Doe"}
      }

      render_hook(view, "trip_accepted", %{"trip" => trip_data})

      html = render(view)
      assert html =~ "Current Trip"
      assert html =~ "Trip Accepted - Navigate to Pickup"
      assert html =~ "John Doe"
      assert html =~ "Start Trip"
      assert html =~ "Cancel Trip"
    end

    test "shows complete trip button when trip is in progress", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Set trip in progress
      trip_data = %{
        "id" => Ecto.UUID.generate(),
        "status" => "in_progress",
        "pickup_location" => %{latitude: 40.7128, longitude: -74.0060},
        "rider_info" => %{"name" => "John Doe"}
      }

      send(view.pid, {:assign, :current_trip, trip_data})

      html = render(view)
      assert html =~ "Trip in Progress"
      assert html =~ "Complete Trip"
      refute html =~ "Start Trip"
    end

    test "handles trip start", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Set accepted trip
      trip_data = %{
        "id" => Ecto.UUID.generate(),
        "status" => "accepted",
        "pickup_location" => %{latitude: 40.7128, longitude: -74.0060},
        "rider_info" => %{"name" => "John Doe"}
      }

      send(view.pid, {:assign, :current_trip, trip_data})

      # Click start trip
      view
      |> element("button", "Start Trip")
      |> render_click()

      # Simulate successful start
      started_trip = Map.put(trip_data, "status", "in_progress")
      render_hook(view, "trip_started", %{"trip" => started_trip})

      html = render(view)
      assert html =~ "Trip started!"
      assert html =~ "Trip in Progress"
    end

    test "handles trip completion", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Set trip in progress
      trip_data = %{
        "id" => Ecto.UUID.generate(),
        "status" => "in_progress",
        "pickup_location" => %{latitude: 40.7128, longitude: -74.0060},
        "rider_info" => %{"name" => "John Doe"}
      }

      send(view.pid, {:assign, :current_trip, trip_data})

      # Click complete trip
      view
      |> element("button", "Complete Trip")
      |> render_click()

      # Simulate successful completion
      completed_trip = Map.merge(trip_data, %{"status" => "completed", "fare" => "15.50"})
      render_hook(view, "trip_completed", %{"trip" => completed_trip})

      html = render(view)
      assert html =~ "Trip completed! Fare: $15.50"
      refute html =~ "Current Trip"
    end

    test "handles trip cancellation", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Set current trip
      trip_data = %{
        "id" => Ecto.UUID.generate(),
        "status" => "accepted",
        "pickup_location" => %{latitude: 40.7128, longitude: -74.0060},
        "rider_info" => %{"name" => "John Doe"}
      }

      send(view.pid, {:assign, :current_trip, trip_data})

      # Send trip cancellation message
      send(view.pid, %{
        event: "trip_cancelled",
        payload: %{
          trip_id: trip_data["id"],
          reason: "Driver cancelled"
        }
      })

      html = render(view)
      assert html =~ "Trip was cancelled: Driver cancelled"
      refute html =~ "Current Trip"
    end

    test "handles trip status updates", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Set current trip
      trip_id = Ecto.UUID.generate()
      trip_data = %{
        "id" => trip_id,
        "status" => "accepted",
        "pickup_location" => %{latitude: 40.7128, longitude: -74.0060},
        "rider_info" => %{"name" => "John Doe"}
      }

      send(view.pid, {:assign, :current_trip, trip_data})

      # Send status update
      send(view.pid, %{
        event: "trip_status_updated",
        payload: %{
          trip_id: trip_id,
          status: "in_progress"
        }
      })

      html = render(view)
      assert html =~ "Trip in Progress"
    end

    test "handles trip errors", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/driver/dashboard")

      # Simulate trip error
      render_hook(view, "trip_error", %{"error" => "Unable to start trip"})

      html = render(view)
      assert html =~ "Trip error: Unable to start trip"
    end
  end
end
