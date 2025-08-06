defmodule Ridex.Repo.Migrations.CreateDriversTable do
  use Ecto.Migration

  def change do
    create table(:drivers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      add :vehicle_info, :map
      add :license_plate, :string
      add :is_active, :boolean, default: false, null: false
      add :availability_status, :string, default: "offline", null: false
      add :current_location, :geometry

      timestamps()
    end

    create unique_index(:drivers, [:user_id])
    create unique_index(:drivers, [:license_plate])
    create index(:drivers, [:is_active])
    create index(:drivers, [:availability_status])
    create index(:drivers, [:is_active, :availability_status])

    # PostGIS spatial index for location queries
    execute "CREATE INDEX drivers_current_location_idx ON drivers USING GIST (current_location);",
            "DROP INDEX drivers_current_location_idx;"
  end
end
