defmodule Ridex.Riders.Rider do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "riders" do
    field :default_pickup_location, Geo.PostGIS.Geometry

    belongs_to :user, Ridex.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(rider, attrs) do
    rider
    |> cast(attrs, [:user_id, :default_pickup_location])
    |> validate_required([:user_id])
    |> validate_location()
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:user_id)
  end

  @doc """
  Changeset for updating rider's default pickup location.
  """
  def location_changeset(rider, attrs) do
    rider
    |> cast(attrs, [:default_pickup_location])
    |> validate_location()
  end

  defp validate_location(changeset) do
    case get_change(changeset, :default_pickup_location) do
      nil -> changeset
      %Geo.Point{coordinates: {lng, lat}} when is_number(lng) and is_number(lat) ->
        if valid_coordinates?(lat, lng) do
          changeset
        else
          add_error(changeset, :default_pickup_location, "invalid coordinates")
        end
      _ ->
        add_error(changeset, :default_pickup_location, "must be a valid point geometry")
    end
  end

  defp valid_coordinates?(lat, lng) do
    lat >= -90 and lat <= 90 and lng >= -180 and lng <= 180
  end
end
