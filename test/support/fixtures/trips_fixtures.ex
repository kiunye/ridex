defmodule Ridex.TripsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ridex.Trips` context.
  """

  alias Ridex.AccountsFixtures
  alias Ridex.DriversFixtures
  alias Ridex.RidersFixtures

  def valid_trip_attributes(attrs \\ %{}) do
    # Default pickup location (NYC coordinates)
    default_pickup = %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}

    # Default destination (slightly different coordinates)
    default_destination = %Geo.Point{coordinates: {-74.0160, 40.7228}, srid: 4326}

    Enum.into(attrs, %{
      pickup_location: default_pickup,
      destination: default_destination,
      status: :requested,
      requested_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  @doc """
  Generate a trip.
  """
  def trip_fixture(attrs \\ %{}) do
    # Ensure we have a rider_id
    rider_id = case Map.get(attrs, :rider_id) do
      nil ->
        rider_user = AccountsFixtures.user_fixture(%{role: :rider})
        rider = RidersFixtures.rider_fixture(%{user_id: rider_user.id})
        rider.id
      rider_id ->
        rider_id
    end

    # Only add driver_id if explicitly provided or if status requires it
    attrs_with_rider = Map.put(attrs, :rider_id, rider_id)

    final_attrs = case {Map.get(attrs, :driver_id), Map.get(attrs, :status)} do
      {nil, status} when status in [:accepted, :in_progress, :completed] ->
        # Create a driver if status requires one but none provided
        driver_user = AccountsFixtures.user_fixture(%{role: :driver})
        driver = DriversFixtures.driver_fixture(%{user_id: driver_user.id})
        Map.put(attrs_with_rider, :driver_id, driver.id)
      _ ->
        attrs_with_rider
    end

    {:ok, trip} =
      final_attrs
      |> valid_trip_attributes()
      |> Ridex.Trips.create_trip_request()

    # Update the trip status if it's not :requested using proper state transitions
    case Map.get(final_attrs, :status, :requested) do
      :requested ->
        trip
      :accepted ->
        driver_id = Map.get(final_attrs, :driver_id)
        {:ok, updated_trip} = Ridex.Trips.accept_trip(trip, driver_id)
        updated_trip
      :in_progress ->
        driver_id = Map.get(final_attrs, :driver_id)
        {:ok, accepted_trip} = Ridex.Trips.accept_trip(trip, driver_id)
        {:ok, updated_trip} = Ridex.Trips.start_trip(accepted_trip)
        updated_trip
      :completed ->
        driver_id = Map.get(final_attrs, :driver_id)
        fare_attrs = Map.take(final_attrs, [:fare])
        {:ok, accepted_trip} = Ridex.Trips.accept_trip(trip, driver_id)
        {:ok, in_progress_trip} = Ridex.Trips.start_trip(accepted_trip)
        {:ok, updated_trip} = Ridex.Trips.complete_trip(in_progress_trip, fare_attrs)
        updated_trip
      :cancelled ->
        reason = Map.get(final_attrs, :cancellation_reason, "Test cancellation")
        {:ok, updated_trip} = Ridex.Trips.cancel_trip(trip, reason)
        updated_trip
    end
  end

  @doc """
  Generate a trip request (always in requested status).
  """
  def trip_request_fixture(attrs \\ %{}) do
    attrs
    |> Map.put(:status, :requested)
    |> Map.delete(:driver_id)  # Requests don't have drivers assigned
    |> trip_fixture()
  end

  @doc """
  Generate an accepted trip.
  """
  def accepted_trip_fixture(attrs \\ %{}) do
    attrs
    |> Map.put(:status, :accepted)
    |> Map.put(:accepted_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> trip_fixture()
  end

  @doc """
  Generate a completed trip.
  """
  def completed_trip_fixture(attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs
    |> Map.put(:status, :completed)
    |> Map.put(:accepted_at, DateTime.add(now, -3600, :second))  # 1 hour ago
    |> Map.put(:started_at, DateTime.add(now, -1800, :second))   # 30 min ago
    |> Map.put(:completed_at, now)
    |> Map.put(:fare, Decimal.new("25.50"))
    |> trip_fixture()
  end

  @doc """
  Generate a cancelled trip.
  """
  def cancelled_trip_fixture(attrs \\ %{}) do
    attrs
    |> Map.put(:status, :cancelled)
    |> Map.put(:cancelled_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> Map.put(:cancellation_reason, "Test cancellation")
    |> trip_fixture()
  end

  @doc """
  Generate a trip in progress.
  """
  def in_progress_trip_fixture(attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs
    |> Map.put(:status, :in_progress)
    |> Map.put(:accepted_at, DateTime.add(now, -1800, :second))  # 30 min ago
    |> Map.put(:started_at, DateTime.add(now, -600, :second))    # 10 min ago
    |> trip_fixture()
  end
end
