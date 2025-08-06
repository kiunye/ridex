defmodule Ridex.Drivers do
  @moduledoc """
  The Drivers context.
  """

  import Ecto.Query, warn: false
  alias Ridex.Repo

  alias Ridex.Drivers.Driver

  @doc """
  Returns the list of drivers.

  ## Examples

      iex> list_drivers()
      [%Driver{}, ...]

  """
  def list_drivers do
    Repo.all(Driver)
  end

  @doc """
  Gets a single driver.

  Raises `Ecto.NoResultsError` if the Driver does not exist.

  ## Examples

      iex> get_driver!(123)
      %Driver{}

      iex> get_driver!(456)
      ** (Ecto.NoResultsError)

  """
  def get_driver!(id), do: Repo.get!(Driver, id)

  @doc """
  Gets a single driver by id.

  ## Examples

      iex> get_driver(123)
      %Driver{}

      iex> get_driver(456)
      nil

  """
  def get_driver(id), do: Repo.get(Driver, id)

  @doc """
  Gets a driver by user_id.

  ## Examples

      iex> get_driver_by_user_id("user-uuid")
      %Driver{}

      iex> get_driver_by_user_id("nonexistent-uuid")
      nil

  """
  def get_driver_by_user_id(user_id) when is_binary(user_id) do
    Repo.get_by(Driver, user_id: user_id)
  end

  @doc """
  Creates a driver profile.

  ## Examples

      iex> create_driver(%{field: value})
      {:ok, %Driver{}}

      iex> create_driver(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_driver(attrs \\ %{}) do
    %Driver{}
    |> Driver.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a driver profile.

  ## Examples

      iex> update_driver(driver, %{field: new_value})
      {:ok, %Driver{}}

      iex> update_driver(driver, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_driver(%Driver{} = driver, attrs) do
    driver
    |> Driver.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates driver location.

  ## Examples

      iex> update_driver_location(driver, %{latitude: 40.7128, longitude: -74.0060})
      {:ok, %Driver{}}

      iex> update_driver_location(driver, %{latitude: "invalid", longitude: -74.0060})
      {:error, %Ecto.Changeset{}}

  """
  def update_driver_location(%Driver{} = driver, %{latitude: lat, longitude: lng})
      when is_number(lat) and is_number(lng) do
    location = %Geo.Point{coordinates: {lng, lat}, srid: 4326}

    driver
    |> Driver.location_changeset(%{current_location: location})
    |> Repo.update()
  end

  @doc """
  Sets driver availability status.

  ## Examples

      iex> set_driver_availability(driver, "active")
      {:ok, %Driver{}}

      iex> set_driver_availability(driver, "invalid_status")
      {:error, %Ecto.Changeset{}}

  """
  def set_driver_availability(%Driver{} = driver, availability_status) do
    driver
    |> Driver.availability_changeset(%{availability_status: availability_status})
    |> Repo.update()
  end

  @doc """
  Activates a driver (sets is_active to true and availability_status to "active").

  ## Examples

      iex> activate_driver(driver)
      {:ok, %Driver{}}

  """
  def activate_driver(%Driver{} = driver) do
    driver
    |> Driver.availability_changeset(%{is_active: true, availability_status: :active})
    |> Repo.update()
  end

  @doc """
  Deactivates a driver (sets is_active to false and availability_status to "offline").

  ## Examples

      iex> deactivate_driver(driver)
      {:ok, %Driver{}}

  """
  def deactivate_driver(%Driver{} = driver) do
    driver
    |> Driver.availability_changeset(%{is_active: false, availability_status: :offline})
    |> Repo.update()
  end

  @doc """
  Returns active drivers within a given radius from a location.

  ## Examples

      iex> get_nearby_active_drivers(40.7128, -74.0060, 5.0)
      [%Driver{}, ...]

  """
  def get_nearby_active_drivers(latitude, longitude, radius_km)
      when is_number(latitude) and is_number(longitude) and is_number(radius_km) do
    point = %Geo.Point{coordinates: {longitude, latitude}, srid: 4326}
    radius_meters = radius_km * 1000

    from(d in Driver,
      where: d.is_active == true,
      where: d.availability_status == :active,
      where: not is_nil(d.current_location),
      where: fragment("ST_DWithin(?::geography, ?::geography, ?)", d.current_location, ^point, ^radius_meters),
      order_by: fragment("ST_Distance(?::geography, ?::geography)", d.current_location, ^point),
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc """
  Returns all active drivers.

  ## Examples

      iex> list_active_drivers()
      [%Driver{}, ...]

  """
  def list_active_drivers do
    from(d in Driver,
      where: d.is_active == true,
      where: d.availability_status == :active,
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc """
  Deletes a driver profile.

  ## Examples

      iex> delete_driver(driver)
      {:ok, %Driver{}}

      iex> delete_driver(driver)
      {:error, %Ecto.Changeset{}}

  """
  def delete_driver(%Driver{} = driver) do
    Repo.delete(driver)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking driver changes.

  ## Examples

      iex> change_driver(driver)
      %Ecto.Changeset{data: %Driver{}}

  """
  def change_driver(%Driver{} = driver, attrs \\ %{}) do
    Driver.changeset(driver, attrs)
  end
end
