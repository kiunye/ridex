defmodule Ridex.Trips do
  @moduledoc """
  The Trips context.
  """

  import Ecto.Query, warn: false
  alias Ridex.Repo

  alias Ridex.Trips.Trip

  @doc """
  Returns the list of trips.

  ## Examples

      iex> list_trips()
      [%Trip{}, ...]

  """
  def list_trips do
    Repo.all(Trip)
  end

  @doc """
  Gets a single trip.

  Raises `Ecto.NoResultsError` if the Trip does not exist.

  ## Examples

      iex> get_trip!(123)
      %Trip{}

      iex> get_trip!(456)
      ** (Ecto.NoResultsError)

  """
  def get_trip!(id), do: Repo.get!(Trip, id)

  @doc """
  Gets a single trip by id.

  ## Examples

      iex> get_trip(123)
      %Trip{}

      iex> get_trip(456)
      nil

  """
  def get_trip(id), do: Repo.get(Trip, id)

  @doc """
  Gets a trip with preloaded associations.

  ## Examples

      iex> get_trip_with_associations(trip_id)
      %Trip{driver: %Driver{}, rider: %Rider{}}

  """
  def get_trip_with_associations(id) do
    Trip
    |> where([t], t.id == ^id)
    |> preload([:driver, :rider])
    |> Repo.one()
  end

  @doc """
  Creates a trip request.

  ## Examples

      iex> create_trip_request(%{rider_id: rider_id, pickup_location: location})
      {:ok, %Trip{}}

      iex> create_trip_request(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_trip_request(attrs \\ %{}) do
    %Trip{}
    |> Trip.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Accepts a trip by assigning a driver.

  ## Examples

      iex> accept_trip(trip, driver_id)
      {:ok, %Trip{}}

      iex> accept_trip(trip, invalid_driver_id)
      {:error, %Ecto.Changeset{}}

  """
  def accept_trip(%Trip{} = trip, driver_id) do
    trip
    |> Trip.accept_changeset(driver_id)
    |> Repo.update()
  end

  @doc """
  Starts a trip (driver begins the journey).

  ## Examples

      iex> start_trip(trip)
      {:ok, %Trip{}}

      iex> start_trip(invalid_trip)
      {:error, %Ecto.Changeset{}}

  """
  def start_trip(%Trip{} = trip) do
    trip
    |> Trip.start_changeset()
    |> Repo.update()
  end

  @doc """
  Completes a trip.

  ## Examples

      iex> complete_trip(trip, %{fare: 25.50})
      {:ok, %Trip{}}

      iex> complete_trip(trip, %{fare: -10})
      {:error, %Ecto.Changeset{}}

  """
  def complete_trip(%Trip{} = trip, attrs \\ %{}) do
    trip
    |> Trip.complete_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Cancels a trip with a reason.

  ## Examples

      iex> cancel_trip(trip, "Driver unavailable")
      {:ok, %Trip{}}

      iex> cancel_trip(completed_trip, "Too late")
      {:error, %Ecto.Changeset{}}

  """
  def cancel_trip(%Trip{} = trip, reason) do
    trip
    |> Trip.cancel_changeset(reason)
    |> Repo.update()
  end

  @doc """
  Updates a trip.

  ## Examples

      iex> update_trip(trip, %{field: new_value})
      {:ok, %Trip{}}

      iex> update_trip(trip, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_trip(%Trip{} = trip, attrs) do
    trip
    |> Trip.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a trip.

  ## Examples

      iex> delete_trip(trip)
      {:ok, %Trip{}}

      iex> delete_trip(trip)
      {:error, %Ecto.Changeset{}}

  """
  def delete_trip(%Trip{} = trip) do
    Repo.delete(trip)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking trip changes.

  ## Examples

      iex> change_trip(trip)
      %Ecto.Changeset{data: %Trip{}}

  """
  def change_trip(%Trip{} = trip, attrs \\ %{}) do
    Trip.changeset(trip, attrs)
  end

  # Query functions for specific use cases

  @doc """
  Gets active trips for a driver.

  ## Examples

      iex> get_active_trips_for_driver(driver_id)
      [%Trip{}, ...]

  """
  def get_active_trips_for_driver(driver_id) do
    from(t in Trip,
      where: t.driver_id == ^driver_id,
      where: t.status in [:accepted, :in_progress],
      order_by: [desc: t.requested_at],
      preload: [:rider]
    )
    |> Repo.all()
  end

  @doc """
  Gets active trips for a rider.

  ## Examples

      iex> get_active_trips_for_rider(rider_id)
      [%Trip{}, ...]

  """
  def get_active_trips_for_rider(rider_id) do
    from(t in Trip,
      where: t.rider_id == ^rider_id,
      where: t.status in [:requested, :accepted, :in_progress],
      order_by: [desc: t.requested_at],
      preload: [:driver]
    )
    |> Repo.all()
  end

  @doc """
  Gets pending trip requests (not yet accepted by any driver).

  ## Examples

      iex> get_pending_trip_requests()
      [%Trip{}, ...]

  """
  def get_pending_trip_requests do
    from(t in Trip,
      where: t.status == :requested,
      where: is_nil(t.driver_id),
      order_by: [asc: t.requested_at],
      preload: [:rider]
    )
    |> Repo.all()
  end

  @doc """
  Gets trip requests within a radius of a location.

  ## Examples

      iex> get_trip_requests_near_location(40.7128, -74.0060, 5.0)
      [%Trip{}, ...]

  """
  def get_trip_requests_near_location(latitude, longitude, radius_km)
      when is_number(latitude) and is_number(longitude) and is_number(radius_km) do
    point = %Geo.Point{coordinates: {longitude, latitude}, srid: 4326}
    radius_meters = radius_km * 1000

    from(t in Trip,
      where: t.status == :requested,
      where: is_nil(t.driver_id),
      where: fragment("ST_DWithin(?::geography, ?::geography, ?)", t.pickup_location, ^point, ^radius_meters),
      order_by: [
        fragment("ST_Distance(?::geography, ?::geography)", t.pickup_location, ^point),
        t.requested_at
      ],
      preload: [:rider]
    )
    |> Repo.all()
  end

  @doc """
  Gets trip history for a user (driver or rider).

  ## Examples

      iex> get_trip_history_for_driver(driver_id, limit: 10)
      [%Trip{}, ...]

      iex> get_trip_history_for_rider(rider_id, limit: 10)
      [%Trip{}, ...]

  """
  def get_trip_history_for_driver(driver_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(t in Trip,
      where: t.driver_id == ^driver_id,
      where: t.status in [:completed, :cancelled],
      order_by: [desc: t.requested_at],
      limit: ^limit,
      preload: [:rider]
    )
    |> Repo.all()
  end

  def get_trip_history_for_rider(rider_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(t in Trip,
      where: t.rider_id == ^rider_id,
      where: t.status in [:completed, :cancelled],
      order_by: [desc: t.requested_at],
      limit: ^limit,
      preload: [:driver]
    )
    |> Repo.all()
  end

  @doc """
  Cancels expired trip requests (older than timeout_minutes).

  ## Examples

      iex> cancel_expired_trip_requests(2)
      {3, nil}  # 3 trips were cancelled

  """
  def cancel_expired_trip_requests(timeout_minutes \\ 2) do
    cutoff_time = DateTime.utc_now() |> DateTime.add(-timeout_minutes, :minute)

    from(t in Trip,
      where: t.status == :requested,
      where: t.requested_at < ^cutoff_time
    )
    |> Repo.update_all(
      set: [
        status: :cancelled,
        cancelled_at: DateTime.utc_now() |> DateTime.truncate(:second),
        cancellation_reason: "Request timeout",
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      ]
    )
  end

  @doc """
  Gets trip statistics for a driver.

  ## Examples

      iex> get_driver_trip_stats(driver_id)
      %{total_trips: 25, completed_trips: 20, cancelled_trips: 5, total_earnings: 450.00}

  """
  def get_driver_trip_stats(driver_id) do
    stats_query = from(t in Trip,
      where: t.driver_id == ^driver_id,
      select: %{
        total_trips: count(t.id),
        completed_trips: filter(count(t.id), t.status == :completed),
        cancelled_trips: filter(count(t.id), t.status == :cancelled),
        total_earnings: sum(t.fare)
      }
    )

    case Repo.one(stats_query) do
      nil -> %{total_trips: 0, completed_trips: 0, cancelled_trips: 0, total_earnings: Decimal.new("0.00")}
      stats ->
        %{stats | total_earnings: stats.total_earnings || Decimal.new("0.00")}
    end
  end

  @doc """
  Gets trip statistics for a rider.

  ## Examples

      iex> get_rider_trip_stats(rider_id)
      %{total_trips: 15, completed_trips: 12, cancelled_trips: 3}

  """
  def get_rider_trip_stats(rider_id) do
    stats_query = from(t in Trip,
      where: t.rider_id == ^rider_id,
      select: %{
        total_trips: count(t.id),
        completed_trips: filter(count(t.id), t.status == :completed),
        cancelled_trips: filter(count(t.id), t.status == :cancelled)
      }
    )

    case Repo.one(stats_query) do
      nil -> %{total_trips: 0, completed_trips: 0, cancelled_trips: 0}
      stats -> stats
    end
  end

  @doc """
  Checks if a driver has any active trips.

  ## Examples

      iex> driver_has_active_trip?(driver_id)
      true

  """
  def driver_has_active_trip?(driver_id) do
    from(t in Trip,
      where: t.driver_id == ^driver_id,
      where: t.status in [:accepted, :in_progress]
    )
    |> Repo.exists?()
  end

  @doc """
  Checks if a rider has any active trips.

  ## Examples

      iex> rider_has_active_trip?(rider_id)
      false

  """
  def rider_has_active_trip?(rider_id) do
    from(t in Trip,
      where: t.rider_id == ^rider_id,
      where: t.status in [:requested, :accepted, :in_progress]
    )
    |> Repo.exists?()
  end
end
