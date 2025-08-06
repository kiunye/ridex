defmodule Ridex.Locations.Location do
  @moduledoc """
  Location schema for tracking user positions over time.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "locations" do
    field :latitude, :decimal
    field :longitude, :decimal
    field :accuracy, :decimal
    field :recorded_at, :utc_datetime

    belongs_to :user, Ridex.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(location, attrs) do
    location
    |> cast(attrs, [:user_id, :latitude, :longitude, :accuracy, :recorded_at])
    |> validate_required([:user_id, :latitude, :longitude])
    |> put_recorded_at_if_missing()
    |> validate_latitude()
    |> validate_longitude()
    |> validate_accuracy()
    |> foreign_key_constraint(:user_id)
  end

  defp put_recorded_at_if_missing(changeset) do
    case get_field(changeset, :recorded_at) do
      nil -> put_change(changeset, :recorded_at, DateTime.utc_now() |> DateTime.truncate(:second))
      _ -> changeset
    end
  end

  defp validate_latitude(changeset) do
    changeset
    |> validate_number(:latitude, greater_than_or_equal_to: -90.0, less_than_or_equal_to: 90.0,
        message: "must be between -90 and 90 degrees")
  end

  defp validate_longitude(changeset) do
    changeset
    |> validate_number(:longitude, greater_than_or_equal_to: -180.0, less_than_or_equal_to: 180.0,
        message: "must be between -180 and 180 degrees")
  end

  defp validate_accuracy(changeset) do
    changeset
    |> validate_number(:accuracy, greater_than: 0.0,
        message: "must be greater than 0")
  end
end
