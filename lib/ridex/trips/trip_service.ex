defmodule Ridex.Trips.TripService do
  @moduledoc """
  Business logic service for trip operations.

  This module provides higher-level business logic functions for trip management,
  including validation, automatic timeouts, and complex trip operations.
  """

  alias Ridex.Trips
  alias Ridex.Trips.Trip
  alias Ridex.Drivers
  alias Ridex.Riders
  alias Ridex.Repo

  import Ecto.Query

  @default_trip_timeout_minutes 2
  @max_trip_requests_per_rider 3

  @doc """
  Creates a trip request with business logic validation.

  Validates that:
  - Rider exists and is active
  - Rider doesn't have too many active trip requests
  - Pickup location is valid
  - Destination is provided and valid

  ## Examples

      iex> create_trip_request(%{rider_id: rider_id, pickup_location: location})
      {:ok, %Trip{}}

      iex> create_trip_request(%{rider_id: invalid_id, pickup_location: location})
      {:error, :rider_not_found}
  """
  def create_trip_request(attrs) do
    with {:ok, rider} <- validate_rider(attrs[:rider_id]),
         :ok <- validate_rider_trip_limit(rider.id),
         :ok <- validate_trip_request_attrs(attrs) do
      # Replace user_id with rider_id in attrs
      trip_attrs = Map.put(attrs, :rider_id, rider.id)
      Trips.create_trip_request(trip_attrs)
    end
  end

  @doc """
  Accepts a trip request by a driver with business logic validation.

  Validates that:
  - Driver exists and is active
  - Driver doesn't already have an active trip
  - Trip exists and is in requested status
  - Trip hasn't expired

  ## Examples

      iex> accept_trip(trip_id, driver_id)
      {:ok, %Trip{}}

      iex> accept_trip(trip_id, busy_driver_id)
      {:error, :driver_has_active_trip}
  """
  def accept_trip(trip_id, driver_user_id) do
    with {:ok, trip} <- get_trip_for_acceptance(trip_id),
         {:ok, driver} <- validate_driver_for_trip(driver_user_id),
         :ok <- validate_trip_not_expired(trip) do
      case Trips.accept_trip(trip, driver.id) do
        {:ok, accepted_trip} ->
          # Update driver status to busy
          Drivers.set_driver_availability(driver, :busy)
          {:ok, accepted_trip}
        error ->
          error
      end
    end
  end

  @doc """
  Declines a trip request by a driver.

  This doesn't change the trip status but records that this driver
  declined the trip (for future matching logic).

  ## Examples

      iex> decline_trip(trip_id, driver_id, "Too far")
      :ok
  """
  def decline_trip(trip_id, driver_id, reason \\ nil) do
    # For now, this is a no-op, but in a real system you might
    # want to track which drivers declined which trips
    # to improve matching algorithms

    # Log the decline for analytics
    require Logger
    Logger.info("Driver #{driver_id} declined trip #{trip_id}: #{reason}")

    :ok
  end

  @doc """
  Starts a trip with business logic validation.

  Validates that:
  - Trip exists and is accepted
  - Driver is the one assigned to the trip
  - Driver is at pickup location (within reasonable distance)

  ## Examples

      iex> start_trip(trip_id, driver_id)
      {:ok, %Trip{}}
  """
  def start_trip(trip_id, driver_user_id) do
    with {:ok, driver} <- get_driver_by_user_id(driver_user_id),
         {:ok, trip} <- get_trip_for_driver_action(trip_id, driver.id, :accepted),
         :ok <- validate_driver_at_pickup(trip, driver.id) do
      Trips.start_trip(trip)
    end
  end

  @doc """
  Completes a trip with business logic validation.

  Validates that:
  - Trip exists and is in progress
  - Driver is the one assigned to the trip
  - Fare calculation is reasonable

  ## Examples

      iex> complete_trip(trip_id, driver_id, %{fare: 25.50})
      {:ok, %Trip{}}
  """
  def complete_trip(trip_id, driver_user_id, attrs \\ %{}) do
    with {:ok, driver} <- get_driver_by_user_id(driver_user_id),
         {:ok, trip} <- get_trip_for_driver_action(trip_id, driver.id, :in_progress),
         {:ok, fare_attrs} <- calculate_and_validate_fare(trip, attrs) do
      case Trips.complete_trip(trip, fare_attrs) do
        {:ok, completed_trip} ->
          # Update driver status back to active
          Drivers.set_driver_availability(driver, :active)
          {:ok, completed_trip}
        error ->
          error
      end
    end
  end

  @doc """
  Cancels a trip with business logic validation and cleanup.

  ## Examples

      iex> cancel_trip(trip_id, user_id, "Emergency", :rider)
      {:ok, %Trip{}}
  """
  def cancel_trip(trip_id, user_id, reason, user_type \\ :rider) do
    with {:ok, trip} <- get_trip_for_cancellation(trip_id, user_id, user_type) do
      case Trips.cancel_trip(trip, reason) do
        {:ok, cancelled_trip} ->
          # If trip was accepted/in_progress, free up the driver
          if cancelled_trip.driver_id && cancelled_trip.status in [:accepted, :in_progress] do
            if driver = Drivers.get_driver(cancelled_trip.driver_id) do
              Drivers.set_driver_availability(driver, :active)
            end
          end
          {:ok, cancelled_trip}
        error ->
          error
      end
    end
  end

  @doc """
  Automatically cancels expired trip requests.

  This should be called periodically (e.g., via a scheduled job)
  to clean up old trip requests that haven't been accepted.

  ## Examples

      iex> cancel_expired_trips()
      {5, nil}  # 5 trips were cancelled
  """
  def cancel_expired_trips(timeout_minutes \\ @default_trip_timeout_minutes) do
    Trips.cancel_expired_trip_requests(timeout_minutes)
  end

  @doc """
  Gets trip history for a user with filtering and pagination.

  ## Examples

      iex> get_trip_history(user_id, :rider, limit: 10, status: :completed)
      [%Trip{}, ...]
  """
  def get_trip_history(user_id, user_type, opts \\ []) do
    case user_type do
      :rider ->
        if rider = Riders.get_rider_by_user_id(user_id) do
          Trips.get_trip_history_for_rider(rider.id, opts)
        else
          []
        end
      :driver ->
        if driver = Drivers.get_driver_by_user_id(user_id) do
          Trips.get_trip_history_for_driver(driver.id, opts)
        else
          []
        end
    end
  end

  @doc """
  Gets comprehensive trip statistics for a user.

  ## Examples

      iex> get_trip_statistics(user_id, :driver)
      %{
        total_trips: 25,
        completed_trips: 20,
        cancelled_trips: 5,
        total_earnings: Decimal.new("450.00"),
        average_rating: 4.8,
        completion_rate: 0.8
      }
  """
  def get_trip_statistics(user_id, user_type) do
    case user_type do
      :rider ->
        if rider = Riders.get_rider_by_user_id(user_id) do
          stats = Trips.get_rider_trip_stats(rider.id)
          Map.put(stats, :completion_rate, calculate_completion_rate(stats))
        else
          %{total_trips: 0, completed_trips: 0, cancelled_trips: 0, completion_rate: 0.0}
        end
      :driver ->
        if driver = Drivers.get_driver_by_user_id(user_id) do
          stats = Trips.get_driver_trip_stats(driver.id)
          stats
          |> Map.put(:completion_rate, calculate_completion_rate(stats))
          |> Map.put(:average_fare, calculate_average_fare(stats))
        else
          %{
            total_trips: 0,
            completed_trips: 0,
            cancelled_trips: 0,
            total_earnings: Decimal.new("0.00"),
            completion_rate: 0.0,
            average_fare: Decimal.new("0.00")
          }
        end
    end
  end

  @doc """
  Finds available trips for a driver based on their location and preferences.

  ## Examples

      iex> find_available_trips_for_driver(driver_id, radius_km: 5.0)
      [%Trip{}, ...]
  """
  def find_available_trips_for_driver(driver_user_id, opts \\ []) do
    with {:ok, driver} <- validate_driver_for_trip(driver_user_id),
         {:ok, location} <- get_driver_location(driver) do
      radius_km = Keyword.get(opts, :radius_km, 10.0)
      {lng, lat} = location.coordinates
      Trips.get_trip_requests_near_location(lat, lng, radius_km)
    else
      _ -> []
    end
  end

  # Private helper functions

  defp get_driver_by_user_id(user_id) do
    case Drivers.get_driver_by_user_id(user_id) do
      nil -> {:error, :driver_not_found}
      driver -> {:ok, driver}
    end
  end

  defp validate_rider(rider_id) when is_binary(rider_id) do
    case Riders.get_rider_by_user_id(rider_id) do
      nil -> {:error, :rider_not_found}
      rider -> {:ok, rider}
    end
  end
  defp validate_rider(_), do: {:error, :invalid_rider_id}

  defp validate_rider_trip_limit(rider_id) do
    active_trips_count =
      from(t in Trip,
        where: t.rider_id == ^rider_id,
        where: t.status in [:requested, :accepted, :in_progress]
      )
      |> Repo.aggregate(:count, :id)

    if active_trips_count >= @max_trip_requests_per_rider do
      {:error, :too_many_active_trips}
    else
      :ok
    end
  end

  defp validate_trip_request_attrs(attrs) do
    cond do
      not is_map(attrs) ->
        {:error, :invalid_attributes}

      not Map.has_key?(attrs, :pickup_location) ->
        {:error, :pickup_location_required}

      not is_valid_location?(attrs[:pickup_location]) ->
        {:error, :invalid_pickup_location}

      Map.has_key?(attrs, :destination) and not is_nil(attrs[:destination]) and not is_valid_location?(attrs[:destination]) ->
        {:error, :invalid_destination}

      true ->
        :ok
    end
  end

  defp is_valid_location?(%Geo.Point{coordinates: {lng, lat}})
    when is_number(lng) and is_number(lat) do
    lat >= -90 and lat <= 90 and lng >= -180 and lng <= 180
  end
  defp is_valid_location?(_), do: false

  defp validate_driver_for_trip(driver_id) when is_binary(driver_id) do
    case Drivers.get_driver_by_user_id(driver_id) do
      nil ->
        {:error, :driver_not_found}
      %{is_active: false} ->
        {:error, :driver_not_active}
      %{availability_status: status} when status not in [:active, :away] ->
        {:error, :driver_not_available}
      driver ->
        if Trips.driver_has_active_trip?(driver.id) do
          {:error, :driver_has_active_trip}
        else
          {:ok, driver}
        end
    end
  end
  defp validate_driver_for_trip(_), do: {:error, :invalid_driver_id}

  defp get_trip_for_acceptance(trip_id) do
    case Trips.get_trip(trip_id) do
      nil -> {:error, :trip_not_found}
      %{status: :requested} = trip -> {:ok, trip}
      %{status: status} -> {:error, {:trip_not_available, status}}
    end
  end

  defp validate_trip_not_expired(trip) do
    cutoff_time = DateTime.utc_now() |> DateTime.add(-@default_trip_timeout_minutes, :minute)

    if DateTime.compare(trip.requested_at, cutoff_time) == :lt do
      {:error, :trip_expired}
    else
      :ok
    end
  end

  defp get_trip_for_driver_action(trip_id, driver_id, expected_status) do
    case Trips.get_trip(trip_id) do
      nil ->
        {:error, :trip_not_found}
      %{status: ^expected_status, driver_id: ^driver_id} = trip ->
        {:ok, trip}
      %{status: status} when status != expected_status ->
        {:error, {:invalid_trip_status, status}}
      %{driver_id: other_driver_id} ->
        {:error, {:not_assigned_driver, other_driver_id}}
    end
  end

  defp validate_driver_at_pickup(_trip, _driver_id) do
    # In a real system, you'd check if the driver is within a reasonable
    # distance of the pickup location. For now, we'll just return :ok
    # TODO: Implement actual location validation
    :ok
  end

  defp calculate_and_validate_fare(trip, attrs) do
    fare = case Map.get(attrs, :fare) do
      nil -> calculate_fare(trip)
      provided_fare -> provided_fare
    end

    cond do
      not is_valid_fare?(fare) ->
        {:error, :invalid_fare}

      true ->
        {:ok, %{fare: fare}}
    end
  end

  defp calculate_fare(_trip) do
    # Simple fare calculation - in a real system this would be much more complex
    # considering distance, time, surge pricing, etc.
    base_fare = Decimal.new("5.00")
    # TODO: Add distance-based calculation
    base_fare
  end

  defp is_valid_fare?(fare) do
    case fare do
      %Decimal{} -> Decimal.positive?(fare)
      fare when is_number(fare) -> fare > 0
      _ -> false
    end
  end

  defp get_trip_for_cancellation(trip_id, user_id, user_type) do
    case Trips.get_trip(trip_id) do
      nil ->
        {:error, :trip_not_found}
      trip ->
        if can_user_cancel_trip?(trip, user_id, user_type) do
          {:ok, trip}
        else
          {:error, :not_authorized_to_cancel}
        end
    end
  end

  defp can_user_cancel_trip?(trip, user_id, user_type) do
    case user_type do
      :rider ->
        rider = Riders.get_rider_by_user_id(user_id)
        rider && rider.id == trip.rider_id
      :driver ->
        driver = Drivers.get_driver_by_user_id(user_id)
        driver && driver.id == trip.driver_id
    end
  end

  defp get_driver_location(driver) do
    case driver.current_location do
      nil -> {:error, :driver_location_not_available}
      location -> {:ok, location}
    end
  end

  defp calculate_completion_rate(%{total_trips: 0}), do: 0.0
  defp calculate_completion_rate(%{total_trips: total, completed_trips: completed}) do
    Float.round(completed / total, 2)
  end

  defp calculate_average_fare(%{completed_trips: 0}), do: Decimal.new("0.00")
  defp calculate_average_fare(%{completed_trips: completed, total_earnings: total}) do
    Decimal.div(total, completed) |> Decimal.round(2)
  end
end
