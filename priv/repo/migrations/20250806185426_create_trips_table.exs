defmodule Ridex.Repo.Migrations.CreateTripsTable do
  use Ecto.Migration

  def change do
    create table(:trips, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :driver_id, references(:drivers, on_delete: :nilify_all, type: :binary_id)
      add :rider_id, references(:riders, on_delete: :delete_all, type: :binary_id), null: false
      add :pickup_location, :geometry, null: false
      add :destination, :geometry
      add :status, :string, null: false, default: "requested"
      add :requested_at, :utc_datetime, null: false
      add :accepted_at, :utc_datetime
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :cancelled_at, :utc_datetime
      add :cancellation_reason, :text
      add :fare, :decimal, precision: 10, scale: 2

      timestamps()
    end

    # Create indexes for efficient queries
    create index(:trips, [:status])
    create index(:trips, [:driver_id])
    create index(:trips, [:rider_id])
    create index(:trips, [:requested_at])
    create index(:trips, [:status, :requested_at])

    # Spatial index for pickup location
    create index(:trips, [:pickup_location], using: :gist)

    # Composite index for active trip queries
    create index(:trips, [:driver_id, :status])
    create index(:trips, [:rider_id, :status])
  end
end
