defmodule Ridex.LocationsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ridex.Locations` context.
  """

  alias Ridex.AccountsFixtures

  def valid_location_attributes(attrs \\ %{}) do
    user = Map.get(attrs, :user) || AccountsFixtures.user_fixture()

    Enum.into(attrs, %{
      user_id: user.id,
      latitude: Decimal.new("40.7128"),
      longitude: Decimal.new("-74.0060"),
      accuracy: Decimal.new("10.5"),
      recorded_at: DateTime.utc_now()
    })
  end

  def location_fixture(attrs \\ %{}) do
    {:ok, location} =
      attrs
      |> valid_location_attributes()
      |> Ridex.Locations.create_location()

    location
  end

  def new_york_coordinates, do: {40.7128, -74.0060}
  def los_angeles_coordinates, do: {34.0522, -118.2437}
  def chicago_coordinates, do: {41.8781, -87.6298}
  def miami_coordinates, do: {25.7617, -80.1918}

  def coordinates_within_radius(center_lat, center_lng, radius_km) do
    # Generate coordinates within the specified radius
    # This is a simplified version for testing
    angle = :rand.uniform() * 2 * :math.pi()
    distance = :rand.uniform() * radius_km

    # Convert to approximate lat/lng offset
    lat_offset = distance * :math.cos(angle) / 111.0  # 1 degree ≈ 111 km
    lng_offset = distance * :math.sin(angle) / (111.0 * :math.cos(center_lat * :math.pi() / 180))

    {center_lat + lat_offset, center_lng + lng_offset}
  end
end
