defmodule Ridex.Drivers.Driver do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "drivers" do
    field :vehicle_info, :map
    field :license_plate, :string
    field :is_active, :boolean, default: false
    field :availability_status, Ecto.Enum,
      values: [:offline, :active, :busy, :away], default: :offline
    field :current_location, Geo.PostGIS.Geometry

    belongs_to :user, Ridex.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(driver, attrs) do
    driver
    |> cast(attrs, [:user_id, :vehicle_info, :license_plate, :is_active, :availability_status, :current_location])
    |> validate_required([:user_id])
    |> validate_vehicle_info()
    |> validate_license_plate()
    |> validate_availability_status()
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:user_id)
    |> unique_constraint(:license_plate)
  end

  @doc """
  Changeset for updating driver location.
  """
  def location_changeset(driver, attrs) do
    driver
    |> cast(attrs, [:current_location])
    |> validate_location()
  end

  @doc """
  Changeset for updating driver availability.
  """
  def availability_changeset(driver, attrs) do
    driver
    |> cast(attrs, [:is_active, :availability_status])
    |> validate_availability_status()
    |> validate_availability_consistency()
  end

  defp validate_vehicle_info(changeset) do
    case get_change(changeset, :vehicle_info) do
      nil -> changeset
      vehicle_info when is_map(vehicle_info) ->
        changeset
        |> validate_vehicle_info_fields(vehicle_info)
      _ ->
        add_error(changeset, :vehicle_info, "must be a valid map")
    end
  end

  defp validate_vehicle_info_fields(changeset, vehicle_info) do
    required_fields = ["make", "model", "year"]

    missing_fields = Enum.filter(required_fields, fn field ->
      not Map.has_key?(vehicle_info, field) or
      vehicle_info[field] == nil or
      vehicle_info[field] == ""
    end)

    case missing_fields do
      [] ->
        changeset
        |> validate_vehicle_year(vehicle_info["year"])
      _ ->
        add_error(changeset, :vehicle_info,
          "must include #{Enum.join(missing_fields, ", ")}")
    end
  end

  defp validate_vehicle_year(changeset, year) when is_integer(year) do
    current_year = Date.utc_today().year

    if year >= 1990 and year <= current_year + 1 do
      changeset
    else
      add_error(changeset, :vehicle_info, "year must be between 1990 and #{current_year + 1}")
    end
  end

  defp validate_vehicle_year(changeset, year) when is_binary(year) do
    case Integer.parse(year) do
      {year_int, ""} -> validate_vehicle_year(changeset, year_int)
      _ -> add_error(changeset, :vehicle_info, "year must be a valid number")
    end
  end

  defp validate_vehicle_year(changeset, _), do: changeset

  defp validate_license_plate(changeset) do
    changeset
    |> validate_format(:license_plate, ~r/^[A-Z0-9\-\s]{2,10}$/i,
        message: "must be 2-10 characters, letters, numbers, hyphens, and spaces only")
    |> update_change(:license_plate, &String.upcase/1)
  end

  defp validate_availability_status(changeset) do
    changeset
    |> validate_inclusion(:availability_status, [:offline, :active, :busy, :away])
  end

  defp validate_availability_consistency(changeset) do
    is_active = get_field(changeset, :is_active)
    availability_status = get_field(changeset, :availability_status)

    # Only validate consistency if both fields are being changed
    case {get_change(changeset, :is_active), get_change(changeset, :availability_status)} do
      {nil, nil} -> changeset  # No changes to either field
      _ ->
        case {is_active, availability_status} do
          {false, status} when status != :offline ->
            add_error(changeset, :availability_status, "must be offline when driver is inactive")
          {true, :offline} ->
            add_error(changeset, :availability_status, "cannot be offline when driver is active")
          _ ->
            changeset
        end
    end
  end

  defp validate_location(changeset) do
    case get_change(changeset, :current_location) do
      nil -> changeset
      %Geo.Point{coordinates: {lng, lat}} when is_number(lng) and is_number(lat) ->
        if valid_coordinates?(lat, lng) do
          changeset
        else
          add_error(changeset, :current_location, "invalid coordinates")
        end
      _ ->
        add_error(changeset, :current_location, "must be a valid point geometry")
    end
  end

  defp valid_coordinates?(lat, lng) do
    lat >= -90 and lat <= 90 and lng >= -180 and lng <= 180
  end
end
