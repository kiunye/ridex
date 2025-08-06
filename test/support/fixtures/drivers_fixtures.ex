defmodule Ridex.DriversFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ridex.Drivers` context.
  """

  alias Ridex.AccountsFixtures

  def valid_driver_attributes(attrs \\ %{}) do
    attrs_map = Enum.into(attrs, %{})

    Enum.into(attrs_map, %{
      vehicle_info: %{
        "make" => "Toyota",
        "model" => "Camry",
        "year" => 2020,
        "color" => "Blue"
      },
      license_plate: "ABC#{System.unique_integer([:positive])}",
      is_active: false,
      availability_status: :offline
    })
  end

  def driver_fixture(attrs \\ %{}) do
    # Create a user with driver role if not provided
    user = case Map.get(attrs, :user) do
      nil -> AccountsFixtures.user_fixture(%{role: :driver})
      user -> user
    end

    driver_attrs =
      attrs
      |> Map.delete(:user)
      |> Map.put(:user_id, user.id)
      |> valid_driver_attributes()

    {:ok, driver} = Ridex.Drivers.create_driver(driver_attrs)

    # Preload user association
    Ridex.Repo.preload(driver, :user)
  end

  def active_driver_fixture(attrs \\ %{}) do
    attrs
    |> Map.merge(%{
      is_active: true,
      availability_status: :active,
      current_location: %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}
    })
    |> driver_fixture()
  end

  def driver_with_location_fixture(latitude, longitude, attrs \\ %{}) do
    location = %Geo.Point{coordinates: {longitude, latitude}, srid: 4326}

    attrs
    |> Map.put(:current_location, location)
    |> driver_fixture()
  end
end
