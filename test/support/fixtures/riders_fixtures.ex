defmodule Ridex.RidersFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ridex.Riders` context.
  """

  alias Ridex.AccountsFixtures

  def valid_rider_attributes(attrs \\ %{}) do
    attrs_map = Enum.into(attrs, %{})

    Enum.into(attrs_map, %{})
  end

  def rider_fixture(attrs \\ %{}) do
    # Create a user with rider role if not provided
    user = case Map.get(attrs, :user) do
      nil -> AccountsFixtures.user_fixture(%{role: :rider})
      user -> user
    end

    rider_attrs =
      attrs
      |> Map.delete(:user)
      |> Map.put(:user_id, user.id)
      |> valid_rider_attributes()

    {:ok, rider} = Ridex.Riders.create_rider(rider_attrs)

    # Store user for test access but don't preload by default
    Map.put(rider, :user, user)
  end

  def rider_with_pickup_location_fixture(latitude, longitude, attrs \\ %{}) do
    location = %Geo.Point{coordinates: {longitude, latitude}, srid: 4326}

    attrs
    |> Map.put(:default_pickup_location, location)
    |> rider_fixture()
  end
end
