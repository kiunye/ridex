defmodule RidexWeb.TripChannel do
  @moduledoc """
  Channel for handling real-time trip-specific communication between drivers and riders.

  This channel provides:
  - Trip status updates
  - Driver-rider messaging during trips
  - Real-time location sharing during active trips
  - Trip state change notifications
  """
  use RidexWeb, :channel

  alias Ridex.Trips
  alias Ridex.LocationService

  @doc """
  Join a trip-specific channel.
  Only the driver and rider assigned to the trip can join.
  """
  def join("trip:" <> trip_id, _payload, socket) do
    current_user = socket.assigns[:current_user]

    case authorize_trip_access(trip_id, current_user) do
      {:ok, trip, user_role} ->
        socket = socket
        |> assign(:trip_id, trip_id)
        |> assign(:trip, trip)
        |> assign(:user_role, user_role)

        # Send current trip status to the joining user
        send(self(), {:after_join, trip})

        {:ok, socket}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  @doc """
  Handle trip status updates (driver actions like start, complete, etc.)
  """
  def handle_in("update_trip_status", %{"status" => status} = payload, socket) do
    trip_id = socket.assigns[:trip_id]
    current_user = socket.assigns[:current_user]
    user_role = socket.assigns[:user_role]

    case handle_trip_status_update(trip_id, status, current_user, user_role, payload) do
      {:ok, updated_trip} ->
        # Broadcast the status update to all trip participants
        broadcast_trip_status_update(trip_id, updated_trip, status, current_user)

        {:reply, {:ok, %{status: "updated", trip_status: updated_trip.status}},
         assign(socket, :trip, updated_trip)}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  def handle_in("location_update", %{"latitude" => lat, "longitude" => lng} = payload, socket) do
    current_user = socket.assigns[:current_user]
    user_role = socket.assigns[:user_role]
    trip = socket.assigns[:trip]

    # Only drivers can send location updates, and only during active trips
    if user_role == :driver and trip.status in [:accepted, :in_progress] do
      accuracy = Map.get(payload, "accuracy")

      case LocationService.update_location(current_user.id, lat, lng, accuracy) do
        {:ok, location} ->
          # Broadcast location to rider
          broadcast_driver_location_update(socket.assigns[:trip_id], current_user, location)
          {:reply, {:ok, %{status: "location_updated"}}, socket}

        {:error, changeset} ->
          errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
          {:reply, {:error, %{errors: errors}}, socket}
      end
    else
      {:reply, {:error, %{reason: "unauthorized_location_update"}}, socket}
    end
  end

  def handle_in("send_message", %{"message" => message} = payload, socket) do
    trip_id = socket.assigns[:trip_id]
    current_user = socket.assigns[:current_user]
    user_role = socket.assigns[:user_role]
    trip = socket.assigns[:trip]

    # Only allow messaging during active trip states
    if trip.status in [:accepted, :in_progress] do
      message_data = %{
        trip_id: trip_id,
        sender_id: current_user.id,
        sender_role: user_role,
        sender_name: current_user.name,
        message: message,
        timestamp: DateTime.utc_now(),
        message_type: Map.get(payload, "message_type", "text")
      }

      # Broadcast message to all trip participants
      broadcast(socket, "message_received", message_data)

      {:reply, {:ok, %{status: "message_sent"}}, socket}
    else
      {:reply, {:error, %{reason: "messaging_not_allowed"}}, socket}
    end
  end

  def handle_in("driver_arrived", _payload, socket) do
    trip_id = socket.assigns[:trip_id]
    current_user = socket.assigns[:current_user]
    user_role = socket.assigns[:user_role]
    trip = socket.assigns[:trip]

    if user_role == :driver and trip.status == :accepted do
      # Notify rider that driver has arrived
      arrival_data = %{
        trip_id: trip_id,
        driver_id: current_user.id,
        driver_name: current_user.name,
        timestamp: DateTime.utc_now()
      }

      broadcast(socket, "driver_arrived", arrival_data)

      {:reply, {:ok, %{status: "arrival_notified"}}, socket}
    else
      {:reply, {:error, %{reason: "unauthorized_arrival_notification"}}, socket}
    end
  end

  def handle_in("cancel_trip", %{"reason" => reason}, socket) do
    trip_id = socket.assigns[:trip_id]
    current_user = socket.assigns[:current_user]
    user_role = socket.assigns[:user_role]

    case Ridex.Trips.TripService.cancel_trip(trip_id, current_user.id, reason, user_role) do
      {:ok, cancelled_trip} ->
        # Broadcast cancellation to all participants
        broadcast_trip_cancellation(trip_id, cancelled_trip, current_user, reason)

        {:reply, {:ok, %{status: "trip_cancelled"}},
         assign(socket, :trip, cancelled_trip)}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  def handle_in("get_trip_info", _payload, socket) do
    trip = socket.assigns[:trip]

    trip_info = %{
      id: trip.id,
      status: trip.status,
      pickup_location: format_location(trip.pickup_location),
      destination: format_location(trip.destination),
      requested_at: trip.requested_at,
      accepted_at: trip.accepted_at,
      started_at: trip.started_at,
      completed_at: trip.completed_at,
      driver_info: get_driver_info(trip),
      rider_info: get_rider_info(trip)
    }

    {:reply, {:ok, %{trip: trip_info}}, socket}
  end

  @doc """
  Handle after join to send initial trip state
  """
  def handle_info({:after_join, trip}, socket) do
    trip_info = %{
      id: trip.id,
      status: trip.status,
      pickup_location: format_location(trip.pickup_location),
      destination: format_location(trip.destination),
      requested_at: trip.requested_at,
      accepted_at: trip.accepted_at,
      started_at: trip.started_at,
      driver_info: get_driver_info(trip),
      rider_info: get_rider_info(trip)
    }

    push(socket, "trip_joined", %{trip: trip_info})
    {:noreply, socket}
  end

  # Private helper functions

  defp authorize_trip_access(trip_id, current_user) do
    case Trips.get_trip_with_associations(trip_id) do
      nil ->
        {:error, "trip_not_found"}

      trip ->
        # Load user associations for driver and rider
        trip = Ridex.Repo.preload(trip, [driver: :user, rider: :user])

        cond do
          trip.driver && trip.driver.user_id == current_user.id ->
            {:ok, trip, :driver}

          trip.rider && trip.rider.user_id == current_user.id ->
            {:ok, trip, :rider}

          true ->
            {:error, "unauthorized"}
        end
    end
  end

  defp handle_trip_status_update(trip_id, status, current_user, user_role, payload) do
    case {status, user_role} do
      {"start", :driver} ->
        Ridex.Trips.TripService.start_trip(trip_id, current_user.id)

      {"complete", :driver} ->
        fare_attrs = Map.take(payload, ["fare"])
        Ridex.Trips.TripService.complete_trip(trip_id, current_user.id, fare_attrs)

      _ ->
        {:error, "invalid_status_update"}
    end
  end

  defp broadcast_trip_status_update(trip_id, trip, _status, user) do
    status_data = %{
      trip_id: trip_id,
      status: trip.status,
      updated_by: user.id,
      updated_by_name: user.name,
      timestamp: DateTime.utc_now(),
      trip_info: %{
        started_at: trip.started_at,
        completed_at: trip.completed_at,
        fare: trip.fare
      }
    }

    RidexWeb.Endpoint.broadcast("trip:#{trip_id}", "trip_status_updated", status_data)
  end

  defp broadcast_driver_location_update(trip_id, driver, location) do
    location_data = %{
      trip_id: trip_id,
      driver_id: driver.id,
      latitude: Decimal.to_float(location.latitude),
      longitude: Decimal.to_float(location.longitude),
      accuracy: location.accuracy && Decimal.to_float(location.accuracy),
      timestamp: location.recorded_at
    }

    RidexWeb.Endpoint.broadcast("trip:#{trip_id}", "driver_location_updated", location_data)
  end

  defp broadcast_trip_cancellation(trip_id, trip, user, reason) do
    cancellation_data = %{
      trip_id: trip_id,
      cancelled_by: user.id,
      cancelled_by_name: user.name,
      reason: reason,
      cancelled_at: trip.cancelled_at,
      timestamp: DateTime.utc_now()
    }

    RidexWeb.Endpoint.broadcast("trip:#{trip_id}", "trip_cancelled", cancellation_data)
  end

  defp format_location(%Geo.Point{coordinates: {lng, lat}}) do
    %{latitude: lat, longitude: lng}
  end
  defp format_location(_), do: nil

  defp get_driver_info(%{driver: nil}), do: nil
  defp get_driver_info(%{driver: driver}) do
    driver = Ridex.Repo.preload(driver, :user)
    %{
      id: driver.id,
      name: driver.user.name,
      vehicle_info: driver.vehicle_info,
      license_plate: driver.license_plate
    }
  end

  defp get_rider_info(%{rider: nil}), do: nil
  defp get_rider_info(%{rider: rider}) do
    rider = Ridex.Repo.preload(rider, :user)
    %{
      id: rider.id,
      name: rider.user.name
    }
  end
end
