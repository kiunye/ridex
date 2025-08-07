defmodule Ridex.Trips.TripTest do
  use Ridex.DataCase

  alias Ridex.Trips.Trip

  import Ridex.RidersFixtures

  describe "trip schema" do
    @valid_pickup_location %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}
    @valid_destination %Geo.Point{coordinates: {-73.9857, 40.7484}, srid: 4326}

    test "create_changeset/2 creates a trip with requested status" do
      rider = rider_fixture()

      attrs = %{
        rider_id: rider.id,
        pickup_location: @valid_pickup_location,
        destination: @valid_destination
      }

      changeset = Trip.create_changeset(%Trip{}, attrs)

      assert changeset.valid?
      # Status should be :requested (either from change or default)
      assert Ecto.Changeset.get_field(changeset, :status) == :requested
      assert get_change(changeset, :rider_id) == rider.id
      assert get_change(changeset, :pickup_location) == @valid_pickup_location
      assert %DateTime{} = get_change(changeset, :requested_at)
    end

    test "accept_changeset/2 transitions from requested to accepted" do
      rider = rider_fixture()
      driver_id = Ecto.UUID.generate()

      trip = %Trip{
        id: Ecto.UUID.generate(),
        rider_id: rider.id,
        pickup_location: @valid_pickup_location,
        status: :requested,
        requested_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      changeset = Trip.accept_changeset(trip, driver_id)

      assert changeset.valid?
      assert get_change(changeset, :status) == :accepted
      assert get_change(changeset, :driver_id) == driver_id
      assert %DateTime{} = get_change(changeset, :accepted_at)
    end

    test "accept_changeset/2 fails when trip is not in requested status" do
      rider = rider_fixture()
      driver_id = Ecto.UUID.generate()

      trip = %Trip{
        id: Ecto.UUID.generate(),
        rider_id: rider.id,
        pickup_location: @valid_pickup_location,
        status: :accepted,  # Already accepted
        requested_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      changeset = Trip.accept_changeset(trip, driver_id)

      refute changeset.valid?
      assert changeset.errors[:status] == {"cannot transition to accepted from accepted", []}
    end

    test "start_changeset/1 transitions from accepted to in_progress" do
      rider = rider_fixture()

      trip = %Trip{
        id: Ecto.UUID.generate(),
        rider_id: rider.id,
        pickup_location: @valid_pickup_location,
        status: :accepted,
        requested_at: DateTime.utc_now() |> DateTime.truncate(:second),
        accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      changeset = Trip.start_changeset(trip)

      assert changeset.valid?
      assert get_change(changeset, :status) == :in_progress
      assert %DateTime{} = get_change(changeset, :started_at)
    end

    test "complete_changeset/2 transitions from in_progress to completed" do
      rider = rider_fixture()

      trip = %Trip{
        id: Ecto.UUID.generate(),
        rider_id: rider.id,
        pickup_location: @valid_pickup_location,
        status: :in_progress,
        requested_at: DateTime.utc_now() |> DateTime.truncate(:second),
        accepted_at: DateTime.utc_now() |> DateTime.truncate(:second),
        started_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      changeset = Trip.complete_changeset(trip, %{fare: Decimal.new("25.50")})

      assert changeset.valid?
      assert get_change(changeset, :status) == :completed
      assert get_change(changeset, :fare) == Decimal.new("25.50")
      assert %DateTime{} = get_change(changeset, :completed_at)
    end

    test "cancel_changeset/2 can cancel from any non-terminal state" do
      rider = rider_fixture()

      # Test cancelling from requested
      trip_requested = %Trip{
        id: Ecto.UUID.generate(),
        rider_id: rider.id,
        pickup_location: @valid_pickup_location,
        status: :requested,
        requested_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      changeset = Trip.cancel_changeset(trip_requested, "User cancelled")
      assert changeset.valid?
      assert get_change(changeset, :status) == :cancelled
      assert get_change(changeset, :cancellation_reason) == "User cancelled"
    end

    test "cancel_changeset/2 fails for completed trips" do
      rider = rider_fixture()

      trip = %Trip{
        id: Ecto.UUID.generate(),
        rider_id: rider.id,
        pickup_location: @valid_pickup_location,
        status: :completed,
        requested_at: DateTime.utc_now() |> DateTime.truncate(:second),
        completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      changeset = Trip.cancel_changeset(trip, "Too late")

      refute changeset.valid?
      assert changeset.errors[:status] == {"cannot cancel a completed trip", []}
    end
  end


end
