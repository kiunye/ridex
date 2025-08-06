defmodule Ridex.Locations do
  @moduledoc """
  The Locations context for managing user location data.
  """

  import Ecto.Query, warn: false
  alias Ridex.Repo
  alias Ridex.Locations.Location

  @doc """
  Creates a location record for a user.

  ## Examples

      iex> create_location(%{user_id: user_id, latitude: 40.7128, longitude: -74.0060})
      {:ok, %Location{}}

      iex> create_location(%{invalid: "data"})
      {:error, %Ecto.Changeset{}}

  """
  def create_location(attrs \\ %{}) do
    %Location{}
    |> Location.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a user's location with current timestamp.
  """
  def update_user_location(user_id, latitude, longitude, accuracy \\ nil) do
    attrs = %{
      user_id: user_id,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      recorded_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    create_location(attrs)
  end

  @doc """
  Gets the most recent location for a user.

  ## Examples

      iex> get_latest_location(user_id)
      %Location{}

      iex> get_latest_location("non-existent")
      nil

  """
  def get_latest_location(user_id) do
    from(l in Location,
      where: l.user_id == ^user_id,
      order_by: [desc: l.recorded_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Gets location history for a user within a time range.
  """
  def get_location_history(user_id, from_datetime, to_datetime) do
    from(l in Location,
      where: l.user_id == ^user_id,
      where: l.recorded_at >= ^from_datetime,
      where: l.recorded_at <= ^to_datetime,
      order_by: [desc: l.recorded_at]
    )
    |> Repo.all()
  end

  @doc """
  Finds users within a specified radius (in kilometers) of a given location.
  Uses the Haversine formula for distance calculation.
  """
  def find_users_within_radius(latitude, longitude, radius_km) do
    # Convert radius from km to degrees (approximate)
    # 1 degree ≈ 111 km at the equator
    radius_degrees = radius_km / 111.0

    # Get the most recent location for each user within the bounding box
    # Using a simpler approach to avoid SQL grouping issues
    from(l in Location,
      distinct: l.user_id,
      where: l.latitude >= ^(latitude - radius_degrees),
      where: l.latitude <= ^(latitude + radius_degrees),
      where: l.longitude >= ^(longitude - radius_degrees),
      where: l.longitude <= ^(longitude + radius_degrees),
      order_by: [l.user_id, desc: l.recorded_at],
      select: %{
        user_id: l.user_id,
        latitude: l.latitude,
        longitude: l.longitude,
        recorded_at: l.recorded_at,
        distance_km: fragment(
          "6371 * acos(greatest(-1, least(1, cos(radians(?)) * cos(radians(?)) * cos(radians(?) - radians(?)) + sin(radians(?)) * sin(radians(?)))))",
          ^latitude, l.latitude, l.longitude, ^longitude, ^latitude, l.latitude
        )
      }
    )
    |> Repo.all()
    |> Enum.filter(fn location -> location.distance_km <= radius_km end)
    |> Enum.sort_by(& &1.distance_km)
  end

  @doc """
  Calculates the distance between two points using the Haversine formula.
  Returns distance in kilometers.
  """
  def calculate_distance(lat1, lon1, lat2, lon2) do
    # Convert degrees to radians
    lat1_rad = lat1 * :math.pi() / 180
    lon1_rad = lon1 * :math.pi() / 180
    lat2_rad = lat2 * :math.pi() / 180
    lon2_rad = lon2 * :math.pi() / 180

    # Haversine formula
    dlat = lat2_rad - lat1_rad
    dlon = lon2_rad - lon1_rad

    a = :math.sin(dlat / 2) * :math.sin(dlat / 2) +
        :math.cos(lat1_rad) * :math.cos(lat2_rad) *
        :math.sin(dlon / 2) * :math.sin(dlon / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))

    # Earth's radius in kilometers
    6371 * c
  end

  @doc """
  Deletes location records older than the specified number of days.
  Used for data cleanup and privacy compliance.
  """
  def cleanup_old_locations(days_to_keep \\ 30) do
    cutoff_date = DateTime.utc_now() |> DateTime.add(-days_to_keep, :day)

    from(l in Location,
      where: l.recorded_at < ^cutoff_date
    )
    |> Repo.delete_all()
  end

  @doc """
  Gets all location records for a user (for testing purposes).
  """
  def list_user_locations(user_id) do
    from(l in Location,
      where: l.user_id == ^user_id,
      order_by: [desc: l.recorded_at]
    )
    |> Repo.all()
  end

  @doc """
  Deletes all location records for a user.
  """
  def delete_user_locations(user_id) do
    from(l in Location,
      where: l.user_id == ^user_id
    )
    |> Repo.delete_all()
  end
end
