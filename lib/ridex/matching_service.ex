defmodule Ridex.MatchingService do
  @moduledoc """
  Service module for driver-rider matching algorithm.

  This module handles the core matching logic for pairing riders with available drivers
  based on proximity, availability, and other scoring factors.
  """

  alias Ridex.Drivers
  alias Ridex.Trips
  alias Ridex.LocationService

  @default_search_radius_km 5.0
  @max_search_radius_km 15.0
  @driver_response_timeout_seconds 30
  @max_drivers_to_notify 5

  @doc """
  Finds available drivers within the specified radius of a pickup location.

  Returns a list of drivers sorted by their matching score (best matches first).

  ## Examples

      iex> find_available_drivers(%Geo.Point{coordinates: {-74.0060, 40.7128}}, 5.0)
      [%{driver: %Driver{}, score: 0.95, distance_km: 1.2}, ...]

      iex> find_available_drivers(invalid_location, 5.0)
      []
  """
  def find_available_drivers(pickup_location) do
    find_available_drivers(pickup_location, @default_search_radius_km)
  end

  def find_available_drivers(%Geo.Point{coordinates: {lng, lat}}, radius_km) do
    find_available_drivers(lat, lng, radius_km)
  end

  def find_available_drivers(latitude, longitude) when is_number(latitude) and is_number(longitude) do
    find_available_drivers(latitude, longitude, @default_search_radius_km)
  end

  def find_available_drivers(_, _), do: []

  def find_available_drivers(latitude, longitude, radius_km)
      when is_number(latitude) and is_number(longitude) and is_number(radius_km) do
    # Get nearby drivers (including both active and away status)
    nearby_drivers = get_nearby_available_drivers(latitude, longitude, radius_km)

    # Filter out drivers who already have active trips
    available_drivers = Enum.reject(nearby_drivers, fn driver ->
      Trips.driver_has_active_trip?(driver.id)
    end)

    # Calculate scores and sort by best match
    available_drivers
    |> Enum.map(fn driver ->
      score = calculate_driver_score(driver, latitude, longitude)
      distance_km = calculate_distance_to_driver(driver, latitude, longitude)

      %{
        driver: driver,
        score: score,
        distance_km: distance_km,
        estimated_arrival_minutes: estimate_arrival_time(distance_km)
      }
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  @doc """
  Calculates a matching score for a driver based on various factors.

  Score factors:
  - Distance (closer is better)
  - Driver availability status
  - Vehicle type compatibility (future enhancement)
  - Driver rating (future enhancement)

  Returns a score between 0.0 and 1.0, where 1.0 is the best match.

  ## Examples

      iex> calculate_driver_score(driver, 40.7128, -74.0060)
      0.85
  """
  def calculate_driver_score(driver, pickup_latitude, pickup_longitude) do
    distance_km = calculate_distance_to_driver(driver, pickup_latitude, pickup_longitude)

    # Base score starts at 1.0 and gets reduced by various factors
    base_score = 1.0

    # Distance penalty: reduce score based on distance
    distance_penalty = calculate_distance_penalty(distance_km)

    # Availability bonus: prefer drivers who are "active" vs "away"
    availability_bonus = calculate_availability_bonus(driver.availability_status)

    # Vehicle type bonus (future enhancement - for now, all vehicles are equal)
    vehicle_bonus = 0.0

    # Calculate final score (ensure it stays between 0.0 and 1.0)
    final_score = base_score - distance_penalty + availability_bonus + vehicle_bonus
    max(0.0, min(1.0, final_score))
  end

  @doc """
  Notifies available drivers about a new ride request.

  Sends notifications to the top-scoring drivers within the search radius.
  Implements a cascading notification system where if the first driver doesn't respond,
  the next best driver is notified.

  ## Examples

      iex> notify_drivers_of_request(trip_id, pickup_location)
      {:ok, %{drivers_notified: 3, notification_ids: [...]}}

      iex> notify_drivers_of_request(trip_id, invalid_location)
      {:error, :no_drivers_available}
  """
  def notify_drivers_of_request(trip_id, pickup_location, opts \\ []) do
    radius_km = Keyword.get(opts, :radius_km, @default_search_radius_km)
    max_drivers = Keyword.get(opts, :max_drivers, @max_drivers_to_notify)

    case find_available_drivers(pickup_location, radius_km) do
      [] ->
        {:error, :no_drivers_available}

      available_drivers ->
        # Take the top drivers to notify
        drivers_to_notify = Enum.take(available_drivers, max_drivers)

        # Send notifications to drivers
        notification_results = Enum.map(drivers_to_notify, fn driver_match ->
          send_ride_request_notification(trip_id, driver_match)
        end)

        successful_notifications = Enum.filter(notification_results, &match?({:ok, _}, &1))

        if length(successful_notifications) > 0 do
          {:ok, %{
            drivers_notified: length(successful_notifications),
            notification_ids: Enum.map(successful_notifications, fn {:ok, id} -> id end),
            drivers: Enum.map(drivers_to_notify, & &1.driver)
          }}
        else
          {:error, :notification_failed}
        end
    end
  end

  @doc """
  Handles a driver's response to a ride request.

  ## Examples

      iex> handle_driver_response(trip_id, driver_id, :accept)
      {:ok, :trip_accepted}

      iex> handle_driver_response(trip_id, driver_id, :decline)
      {:ok, :trip_declined}
  """
  def handle_driver_response(trip_id, driver_user_id, response) do
    case response do
      :accept ->
        handle_trip_acceptance(trip_id, driver_user_id)

      :decline ->
        handle_trip_decline(trip_id, driver_user_id)

      _ ->
        {:error, :invalid_response}
    end
  end

  @doc """
  Expands the search radius and retries matching when no drivers are found.

  ## Examples

      iex> retry_with_expanded_radius(trip_id)
      {:ok, %{drivers_notified: 2, expanded_radius: 10.0}}

      iex> retry_with_expanded_radius(trip_id)
      {:error, :no_drivers_found_in_expanded_search}
  """
  def retry_with_expanded_radius(trip_id, current_radius_km \\ @default_search_radius_km) do
    case Trips.get_trip(trip_id) do
      nil ->
        {:error, :trip_not_found}

      %{status: :requested, pickup_location: pickup_location} = _trip ->
        expanded_radius = min(current_radius_km * 2, @max_search_radius_km)

        case notify_drivers_of_request(trip_id, pickup_location, radius_km: expanded_radius) do
          {:ok, result} ->
            {:ok, Map.put(result, :expanded_radius, expanded_radius)}

          {:error, :no_drivers_available} when expanded_radius < @max_search_radius_km ->
            retry_with_expanded_radius(trip_id, expanded_radius)

          error ->
            error
        end

      %{status: status} ->
        {:error, {:trip_not_available, status}}
    end
  end

  @doc """
  Gets matching statistics for analytics and monitoring.

  ## Examples

      iex> get_matching_statistics()
      %{
        average_match_time_seconds: 15.3,
        success_rate: 0.87,
        average_drivers_per_request: 2.4
      }
  """
  def get_matching_statistics(_hours_back \\ 24) do
    # This would typically query a metrics/analytics table
    # For now, return mock data
    %{
      average_match_time_seconds: 18.5,
      success_rate: 0.82,
      average_drivers_per_request: 2.1,
      total_requests: 0,
      successful_matches: 0
    }
  end

  # Private helper functions

  defp get_nearby_available_drivers(latitude, longitude, radius_km) do
    # Use a more inclusive query that includes both :active and :away drivers
    point = %Geo.Point{coordinates: {longitude, latitude}, srid: 4326}
    radius_meters = radius_km * 1000

    import Ecto.Query

    from(d in Ridex.Drivers.Driver,
      where: d.is_active == true,
      where: d.availability_status in [:active, :away],
      where: not is_nil(d.current_location),
      where: fragment("ST_DWithin(?::geography, ?::geography, ?)", d.current_location, ^point, ^radius_meters),
      order_by: fragment("ST_Distance(?::geography, ?::geography)", d.current_location, ^point),
      preload: [:user]
    )
    |> Ridex.Repo.all()
  end

  defp calculate_distance_to_driver(driver, latitude, longitude) do
    case driver.current_location do
      %Geo.Point{coordinates: {lng, lat}} ->
        LocationService.calculate_distance(latitude, longitude, lat, lng)

      _ ->
        # If no location available, return a high distance to deprioritize
        999.0
    end
  end

  defp calculate_distance_penalty(distance_km) do
    # Linear penalty: 0.1 penalty per km, max 0.5 penalty at 5km
    # Special case for very high distances (no location)
    if distance_km > 100 do
      0.9  # Heavy penalty for drivers without location
    else
      penalty = distance_km * 0.1
      min(penalty, 0.5)
    end
  end

  defp calculate_availability_bonus(availability_status) do
    case availability_status do
      :active -> 0.1
      :away -> 0.0
      _ -> -0.2
    end
  end

  defp estimate_arrival_time(distance_km) do
    # Simple estimation: assume 30 km/h average speed in city
    average_speed_kmh = 30.0
    time_hours = distance_km / average_speed_kmh
    round(time_hours * 60)  # Convert to minutes
  end

  defp send_ride_request_notification(trip_id, driver_match) do
    driver = driver_match.driver

    # Create notification payload
    notification_data = %{
      trip_id: trip_id,
      pickup_location: get_pickup_location_for_notification(trip_id),
      estimated_arrival: driver_match.estimated_arrival_minutes,
      distance_km: driver_match.distance_km,
      expires_at: DateTime.utc_now() |> DateTime.add(@driver_response_timeout_seconds, :second)
    }

    # Broadcast to driver's channel
    case RidexWeb.Endpoint.broadcast(
      "user:#{driver.user_id}",
      "ride_request",
      notification_data
    ) do
      :ok ->
        # Schedule timeout for this notification
        schedule_notification_timeout(trip_id, driver.user_id)
        {:ok, "#{trip_id}_#{driver.user_id}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_pickup_location_for_notification(trip_id) do
    case Trips.get_trip(trip_id) do
      %{pickup_location: %Geo.Point{coordinates: {lng, lat}}} ->
        %{latitude: lat, longitude: lng}
      _ ->
        nil
    end
  end

  defp schedule_notification_timeout(trip_id, driver_user_id) do
    # In a production system, you'd use a job queue like Oban
    # For now, we'll use Process.send_after for simplicity
    Process.send_after(
      self(),
      {:notification_timeout, trip_id, driver_user_id},
      @driver_response_timeout_seconds * 1000
    )
  end

  defp handle_trip_acceptance(trip_id, driver_user_id) do
    case Ridex.Trips.TripService.accept_trip(trip_id, driver_user_id) do
      {:ok, trip} ->
        # Cancel notifications to other drivers
        cancel_other_driver_notifications(trip_id, driver_user_id)

        # Notify rider that driver accepted
        notify_rider_of_acceptance(trip)

        {:ok, :trip_accepted}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_trip_decline(trip_id, driver_user_id) do
    # Log the decline
    require Logger
    Logger.info("Driver #{driver_user_id} declined trip #{trip_id}")

    # Check if we should notify the next available driver
    case should_notify_next_driver?(trip_id) do
      true ->
        notify_next_available_driver(trip_id)
      false ->
        :ok
    end

    {:ok, :trip_declined}
  end

  defp cancel_other_driver_notifications(trip_id, accepting_driver_user_id) do
    # Broadcast cancellation to all drivers except the accepting one
    RidexWeb.Endpoint.broadcast(
      "trip:#{trip_id}",
      "ride_request_cancelled",
      %{
        trip_id: trip_id,
        reason: "accepted_by_another_driver",
        accepting_driver: accepting_driver_user_id
      }
    )
  end

  defp notify_rider_of_acceptance(trip) do
    case trip.rider_id do
      nil -> :ok
      rider_id ->
        # Get rider's user_id
        case Ridex.Riders.get_rider(rider_id) do
          nil -> :ok
          rider ->
            RidexWeb.Endpoint.broadcast(
              "user:#{rider.user_id}",
              "trip_accepted",
              %{
                trip_id: trip.id,
                driver_info: get_driver_info_for_rider(trip.driver_id),
                status: trip.status
              }
            )
        end
    end
  end

  defp get_driver_info_for_rider(driver_id) do
    case Drivers.get_driver(driver_id) do
      nil -> %{}
      driver ->
        # Load user association if not already loaded
        driver = Ridex.Repo.preload(driver, :user)
        %{
          name: driver.user && driver.user.name,
          vehicle_info: driver.vehicle_info,
          license_plate: driver.license_plate,
          current_location: format_location_for_broadcast(driver.current_location)
        }
    end
  end

  defp format_location_for_broadcast(%Geo.Point{coordinates: {lng, lat}}) do
    %{latitude: lat, longitude: lng}
  end
  defp format_location_for_broadcast(_), do: nil

  defp should_notify_next_driver?(trip_id) do
    case Trips.get_trip(trip_id) do
      %{status: :requested} -> true
      _ -> false
    end
  end

  defp notify_next_available_driver(trip_id) do
    case Trips.get_trip(trip_id) do
      %{pickup_location: _pickup_location} ->
        # Try to find more drivers with expanded radius
        retry_with_expanded_radius(trip_id)
      _ ->
        :ok
    end
  end
end
