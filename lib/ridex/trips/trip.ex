defmodule Ridex.Trips.Trip do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "trips" do
    field :pickup_location, Geo.PostGIS.Geometry
    field :destination, Geo.PostGIS.Geometry
    field :status, Ecto.Enum,
      values: [:requested, :accepted, :in_progress, :completed, :cancelled],
      default: :requested
    field :requested_at, :utc_datetime
    field :accepted_at, :utc_datetime
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :cancelled_at, :utc_datetime
    field :cancellation_reason, :string
    field :fare, :decimal

    belongs_to :driver, Ridex.Drivers.Driver
    belongs_to :rider, Ridex.Riders.Rider

    timestamps()
  end

  @doc false
  def changeset(trip, attrs) do
    trip
    |> cast(attrs, [
      :rider_id, :driver_id, :pickup_location, :destination,
      :status, :requested_at, :accepted_at, :started_at,
      :completed_at, :cancelled_at, :cancellation_reason, :fare
    ])
    |> validate_required([:rider_id, :pickup_location, :status])
    |> validate_pickup_location()
    |> validate_destination()
    |> validate_status_transitions()
    |> validate_timestamps()
    |> foreign_key_constraint(:driver_id)
    |> foreign_key_constraint(:rider_id)
    |> put_requested_at()
  end

  @doc """
  Changeset for creating a new trip request.
  """
  def create_changeset(trip, attrs) do
    trip
    |> cast(attrs, [:rider_id, :pickup_location, :destination])
    |> validate_required([:rider_id, :pickup_location])
    |> validate_pickup_location()
    |> validate_destination()
    |> put_change(:status, :requested)
    |> put_change(:requested_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> foreign_key_constraint(:rider_id)
  end

  @doc """
  Changeset for accepting a trip.
  """
  def accept_changeset(trip, driver_id) do
    trip
    |> change()
    |> put_change(:driver_id, driver_id)
    |> put_change(:status, :accepted)
    |> put_change(:accepted_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> validate_status_transition(:requested, :accepted)
    |> foreign_key_constraint(:driver_id)
  end

  @doc """
  Changeset for starting a trip.
  """
  def start_changeset(trip) do
    trip
    |> change()
    |> put_change(:status, :in_progress)
    |> put_change(:started_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> validate_status_transition(:accepted, :in_progress)
  end

  @doc """
  Changeset for completing a trip.
  """
  def complete_changeset(trip, attrs \\ %{}) do
    trip
    |> cast(attrs, [:fare])
    |> put_change(:status, :completed)
    |> put_change(:completed_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> validate_status_transition(:in_progress, :completed)
    |> validate_number(:fare, greater_than: 0)
  end

  @doc """
  Changeset for cancelling a trip.
  """
  def cancel_changeset(trip, reason) do
    trip
    |> change()
    |> put_change(:status, :cancelled)
    |> put_change(:cancelled_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> put_change(:cancellation_reason, reason)
    |> validate_cancellation_allowed()
  end

  # Private helper functions

  defp validate_pickup_location(changeset) do
    validate_location(changeset, :pickup_location)
  end

  defp validate_destination(changeset) do
    validate_location(changeset, :destination)
  end

  defp validate_location(changeset, field) do
    case get_change(changeset, field) do
      nil -> changeset
      %Geo.Point{coordinates: {lng, lat}} when is_number(lng) and is_number(lat) ->
        if valid_coordinates?(lat, lng) do
          changeset
        else
          add_error(changeset, field, "invalid coordinates")
        end
      _ ->
        add_error(changeset, field, "must be a valid point geometry")
    end
  end

  defp valid_coordinates?(lat, lng) do
    lat >= -90 and lat <= 90 and lng >= -180 and lng <= 180
  end

  defp validate_status_transitions(changeset) do
    case get_change(changeset, :status) do
      nil -> changeset
      new_status ->
        current_status = get_field(changeset, :status)
        if valid_status_transition?(current_status, new_status) do
          changeset
        else
          add_error(changeset, :status, "invalid status transition from #{current_status} to #{new_status}")
        end
    end
  end

  defp validate_status_transition(changeset, expected_current, new_status) do
    # Get the original status from the data, not the changeset
    current_status = changeset.data.status
    if current_status == expected_current do
      changeset
    else
      add_error(changeset, :status, "cannot transition to #{new_status} from #{current_status}")
    end
  end

  defp valid_status_transition?(current, new) do
    case {current, new} do
      # Initial state
      {nil, :requested} -> true

      # From requested
      {:requested, :accepted} -> true
      {:requested, :cancelled} -> true

      # From accepted
      {:accepted, :in_progress} -> true
      {:accepted, :cancelled} -> true

      # From in_progress
      {:in_progress, :completed} -> true
      {:in_progress, :cancelled} -> true

      # Terminal states cannot transition
      {:completed, _} -> false
      {:cancelled, _} -> false

      # Any other transition is invalid
      _ -> false
    end
  end

  defp validate_cancellation_allowed(changeset) do
    # Check the original status from the data, not the changeset
    current_status = changeset.data.status
    if current_status in [:completed] do
      add_error(changeset, :status, "cannot cancel a completed trip")
    else
      changeset
    end
  end

  defp validate_timestamps(changeset) do
    changeset
    |> validate_timestamp_order(:requested_at, :accepted_at)
    |> validate_timestamp_order(:accepted_at, :started_at)
    |> validate_timestamp_order(:started_at, :completed_at)
  end

  defp validate_timestamp_order(changeset, earlier_field, later_field) do
    earlier = get_field(changeset, earlier_field)
    later = get_field(changeset, later_field)

    case {earlier, later} do
      {nil, _} -> changeset
      {_, nil} -> changeset
      {earlier_time, later_time} ->
        if DateTime.compare(earlier_time, later_time) in [:lt, :eq] do
          changeset
        else
          add_error(changeset, later_field, "must be after #{earlier_field}")
        end
    end
  end

  defp put_requested_at(changeset) do
    case get_field(changeset, :requested_at) do
      nil -> put_change(changeset, :requested_at, DateTime.utc_now() |> DateTime.truncate(:second))
      _ -> changeset
    end
  end

  @doc """
  Returns true if the trip is in an active state (not completed or cancelled).
  """
  def active?(%__MODULE__{status: status}) do
    status in [:requested, :accepted, :in_progress]
  end

  @doc """
  Returns true if the trip is in a terminal state (completed or cancelled).
  """
  def terminal?(%__MODULE__{status: status}) do
    status in [:completed, :cancelled]
  end

  @doc """
  Returns the duration of the trip in seconds, if applicable.
  """
  def duration(%__MODULE__{started_at: nil}), do: nil
  def duration(%__MODULE__{started_at: _started_at, completed_at: nil}), do: nil
  def duration(%__MODULE__{started_at: started_at, completed_at: completed_at}) do
    DateTime.diff(completed_at, started_at, :second)
  end
end
