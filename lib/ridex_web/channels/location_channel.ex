defmodule RidexWeb.LocationChannel do
  @moduledoc """
  Channel for handling real-time location updates and broadcasting.
  """
  use RidexWeb, :channel

  alias Ridex.LocationService
  alias Ridex.Drivers

  @doc """
  Join the location updates channel.
  Only authenticated users can join.
  """
  def join("location:updates", _payload, socket) do
    if socket.assigns[:current_user] do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def join("location:user:" <> user_id, _payload, socket) do
    current_user = socket.assigns[:current_user]

    if current_user && current_user.id == user_id do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @doc """
  Handle location updates from clients.
  """
  def handle_in("location_update", %{"latitude" => lat, "longitude" => lng} = payload, socket) do
    user = socket.assigns[:current_user]
    accuracy = Map.get(payload, "accuracy")

    case LocationService.update_location(user.id, lat, lng, accuracy) do
      {:ok, location} ->
        # Broadcast the location update to relevant channels
        broadcast_location_update(user, location)
        {:reply, {:ok, %{status: "location_updated"}}, socket}

      {:error, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        {:reply, {:error, %{errors: errors}}, socket}
    end
  end

  def handle_in("request_nearby_drivers", %{"latitude" => lat, "longitude" => lng} = payload, socket) do
    radius_km = Map.get(payload, "radius_km", 5.0)

    nearby_drivers = LocationService.get_nearby_drivers(lat, lng, radius_km)

    {:reply, {:ok, %{drivers: nearby_drivers}}, socket}
  end

  def handle_in("driver_checkin", %{"latitude" => lat, "longitude" => lng} = payload, socket) do
    user = socket.assigns[:current_user]
    accuracy = Map.get(payload, "accuracy")

    # Verify user is a driver
    case Drivers.get_driver_by_user_id(user.id) do
      nil ->
        {:reply, {:error, %{reason: "not_a_driver"}}, socket}

      driver ->
        # Activate driver and start location tracking
        with {:ok, _driver} <- Drivers.activate_driver(driver),
             {:ok, location} <- LocationService.start_location_tracking(user.id, lat, lng, accuracy) do

          # Broadcast driver availability
          broadcast_driver_status_change(user, "active")
          broadcast_location_update(user, location)

          {:reply, {:ok, %{status: "checked_in"}}, socket}
        else
          {:error, changeset} ->
            errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
            {:reply, {:error, %{errors: errors}}, socket}
        end
    end
  end

  def handle_in("driver_checkout", _payload, socket) do
    user = socket.assigns[:current_user]

    case Drivers.get_driver_by_user_id(user.id) do
      nil ->
        {:reply, {:error, %{reason: "not_a_driver"}}, socket}

      driver ->
        # Deactivate driver and stop location tracking
        with {:ok, _driver} <- Drivers.deactivate_driver(driver),
             :ok <- LocationService.stop_location_tracking(user.id) do

          # Broadcast driver unavailability
          broadcast_driver_status_change(user, "offline")

          {:reply, {:ok, %{status: "checked_out"}}, socket}
        else
          {:error, changeset} ->
            errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
            {:reply, {:error, %{errors: errors}}, socket}
        end
    end
  end

  def handle_in("get_current_location", %{"user_id" => user_id}, socket) do
    current_user = socket.assigns[:current_user]

    # Only allow users to get their own location or drivers to get rider locations during trips
    if current_user.id == user_id or authorized_to_view_location?(current_user, user_id) do
      case LocationService.get_current_location(user_id) do
        nil ->
          {:reply, {:error, %{reason: "location_not_found"}}, socket}

        location ->
          location_data = %{
            latitude: Decimal.to_float(location.latitude),
            longitude: Decimal.to_float(location.longitude),
            accuracy: location.accuracy && Decimal.to_float(location.accuracy),
            recorded_at: location.recorded_at
          }
          {:reply, {:ok, %{location: location_data}}, socket}
      end
    else
      {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  # Private helper functions

  defp broadcast_location_update(user, location) do
    location_data = %{
      user_id: user.id,
      latitude: Decimal.to_float(location.latitude),
      longitude: Decimal.to_float(location.longitude),
      accuracy: location.accuracy && Decimal.to_float(location.accuracy),
      recorded_at: location.recorded_at
    }

    # Broadcast to general location updates channel
    RidexWeb.Endpoint.broadcast("location:updates", "location_updated", location_data)

    # Broadcast to user's specific channel
    RidexWeb.Endpoint.broadcast("location:user:#{user.id}", "location_updated", location_data)

    # If user is a driver, broadcast to driver-specific channels
    if user.role == :driver do
      RidexWeb.Endpoint.broadcast("drivers:locations", "driver_location_updated", location_data)
    end
  end

  defp broadcast_driver_status_change(user, status) do
    driver_data = %{
      user_id: user.id,
      status: status,
      timestamp: DateTime.utc_now()
    }

    RidexWeb.Endpoint.broadcast("drivers:status", "driver_status_changed", driver_data)
    RidexWeb.Endpoint.broadcast("location:updates", "driver_status_changed", driver_data)
  end

  defp authorized_to_view_location?(_current_user, _user_id) do
    # TODO: Implement proper authorization logic for trips
    # For now, return false - only users can see their own locations
    false
  end
end
