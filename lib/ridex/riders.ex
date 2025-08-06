defmodule Ridex.Riders do
  @moduledoc """
  The Riders context.
  """

  import Ecto.Query, warn: false
  alias Ridex.Repo

  alias Ridex.Riders.Rider

  @doc """
  Returns the list of riders.

  ## Examples

      iex> list_riders()
      [%Rider{}, ...]

  """
  def list_riders do
    Repo.all(Rider)
  end

  @doc """
  Gets a single rider.

  Raises `Ecto.NoResultsError` if the Rider does not exist.

  ## Examples

      iex> get_rider!(123)
      %Rider{}

      iex> get_rider!(456)
      ** (Ecto.NoResultsError)

  """
  def get_rider!(id), do: Repo.get!(Rider, id)

  @doc """
  Gets a single rider by id.

  ## Examples

      iex> get_rider(123)
      %Rider{}

      iex> get_rider(456)
      nil

  """
  def get_rider(id), do: Repo.get(Rider, id)

  @doc """
  Gets a rider by user_id.

  ## Examples

      iex> get_rider_by_user_id("user-uuid")
      %Rider{}

      iex> get_rider_by_user_id("nonexistent-uuid")
      nil

  """
  def get_rider_by_user_id(user_id) when is_binary(user_id) do
    Repo.get_by(Rider, user_id: user_id)
  end

  @doc """
  Creates a rider profile.

  ## Examples

      iex> create_rider(%{field: value})
      {:ok, %Rider{}}

      iex> create_rider(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_rider(attrs \\ %{}) do
    %Rider{}
    |> Rider.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a rider profile.

  ## Examples

      iex> update_rider(rider, %{field: new_value})
      {:ok, %Rider{}}

      iex> update_rider(rider, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_rider(%Rider{} = rider, attrs) do
    rider
    |> Rider.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates rider's default pickup location.

  ## Examples

      iex> update_rider_pickup_location(rider, %{latitude: 40.7128, longitude: -74.0060})
      {:ok, %Rider{}}

      iex> update_rider_pickup_location(rider, %{latitude: "invalid", longitude: -74.0060})
      {:error, %Ecto.Changeset{}}

  """
  def update_rider_pickup_location(%Rider{} = rider, %{latitude: lat, longitude: lng})
      when is_number(lat) and is_number(lng) do
    location = %Geo.Point{coordinates: {lng, lat}, srid: 4326}

    rider
    |> Rider.location_changeset(%{default_pickup_location: location})
    |> Repo.update()
  end

  @doc """
  Deletes a rider profile.

  ## Examples

      iex> delete_rider(rider)
      {:ok, %Rider{}}

      iex> delete_rider(rider)
      {:error, %Ecto.Changeset{}}

  """
  def delete_rider(%Rider{} = rider) do
    Repo.delete(rider)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking rider changes.

  ## Examples

      iex> change_rider(rider)
      %Ecto.Changeset{data: %Rider{}}

  """
  def change_rider(%Rider{} = rider, attrs \\ %{}) do
    Rider.changeset(rider, attrs)
  end
end
