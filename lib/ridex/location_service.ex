defmodule Ridex.LocationService do
  @moduledoc """
  Service module for location tracking and management.
  Provides high-level functions for location updates, retrieval, and proximity calculations.
  """

  alias Ridex.Locations
  alias Ridex.Drivers

  @doc """
  Starts location tracking for a user by updating their location.
  """
  def start_location_tracking(user_id, latitude, longitude, accuracy \\ nil) do
    case Locations.update_user_location(user_id, latitude, longitude, accuracy) do
      {:ok, location} ->
        # If this is a driver, also update their current_location in the drivers table
        update_driver_location_if_applicable(user_id, latitude, longitude)
        {:ok, location}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Stops location tracking for a user by cleaning up their location data.
  """
  def stop_location_tracking(user_id) do
    # Set driver location to nil if applicable
    clear_driver_location_if_applicable(user_id)

    # Note: We don't delete location history for privacy/audit purposes
    # Location cleanup happens via scheduled job
    :ok
  end

  @doc """
  Updates a user's location with validation and driver table sync.
  """
  def update_location(user_id, latitude, longitude, accuracy \\ nil) do
    with {:ok, location} <- Locations.update_user_location(user_id, latitude, longitude, accuracy) do
      # Update driver location if this user is a driver
      update_driver_location_if_applicable(user_id, latitude, longitude)
      {:ok, location}
    end
  end

  @doc """
  Gets the current location for a user.
  """
  def get_current_location(user_id) do
    Locations.get_latest_location(user_id)
  end

  @doc """
  Finds nearby drivers within the specified radius.
  Returns a list of driver information with their locations and distances.
  """
  def get_nearby_drivers(latitude, longitude, radius_km \\ 5.0) do
    # Get users within radius
    nearby_users = Locations.find_users_within_radius(latitude, longitude, radius_km)

    # Filter for active drivers only
    nearby_users
    |> Enum.map(fn user_location ->
      case Drivers.get_driver_by_user_id(user_location.user_id) do
        %{is_active: true, availability_status: :active} = driver ->
          %{
            driver_id: driver.id,
            user_id: user_location.user_id,
            latitude: Decimal.to_float(user_location.latitude),
            longitude: Decimal.to_float(user_location.longitude),
            distance_km: user_location.distance_km,
            last_updated: user_location.recorded_at,
            vehicle_info: driver.vehicle_info,
            license_plate: driver.license_plate
          }
        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.distance_km)
  end

  @doc """
  Calculates distance between two geographic points.
  """
  def calculate_distance(lat1, lon1, lat2, lon2) do
    Locations.calculate_distance(lat1, lon1, lat2, lon2)
  end

  @doc """
  Validates if a location is within acceptable accuracy bounds.
  """
  def is_location_accurate?(accuracy, max_accuracy_meters \\ 100.0) do
    case accuracy do
      nil -> true  # Accept locations without accuracy data
      acc when is_number(acc) -> acc <= max_accuracy_meters
      _ -> false
    end
  end

  @doc """
  Gets location history for a user within a time range.
  """
  def get_location_history(user_id, hours_back \\ 24) do
    from_datetime = DateTime.utc_now() |> DateTime.add(-hours_back, :hour)
    to_datetime = DateTime.utc_now()

    Locations.get_location_history(user_id, from_datetime, to_datetime)
  end

  @doc """
  Broadcasts a location update to relevant channels.
  """
  def broadcast_location_update(user_id, location) do
    location_data = %{
      user_id: user_id,
      latitude: Decimal.to_float(location.latitude),
      longitude: Decimal.to_float(location.longitude),
      accuracy: location.accuracy && Decimal.to_float(location.accuracy),
      recorded_at: location.recorded_at
    }

    # Broadcast to general location updates channel
    RidexWeb.Endpoint.broadcast("location:updates", "location_updated", location_data)

    # Broadcast to user's specific channel
    RidexWeb.Endpoint.broadcast("location:user:#{user_id}", "location_updated", location_data)

    {:ok, location}
  end

  # Private helper functions

  defp update_driver_location_if_applicable(user_id, latitude, longitude) do
    case Drivers.get_driver_by_user_id(user_id) do
      nil ->
        :ok
      driver ->
        # Create a PostGIS point for the driver's current location
        point = %Geo.Point{coordinates: {longitude, latitude}, srid: 4326}
        Drivers.update_driver_location(driver, point)
    end
  end

  defp clear_driver_location_if_applicable(user_id) do
    case Drivers.get_driver_by_user_id(user_id) do
      nil ->
        :ok
      driver ->
        Drivers.update_driver_location(driver, nil)
    end
  end
end
