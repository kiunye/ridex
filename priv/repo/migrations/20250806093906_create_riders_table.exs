defmodule Ridex.Repo.Migrations.CreateRidersTable do
  use Ecto.Migration

  def change do
    create table(:riders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      add :default_pickup_location, :geometry

      timestamps()
    end

    create unique_index(:riders, [:user_id])

    # PostGIS spatial index for location queries
    execute "CREATE INDEX riders_default_pickup_location_idx ON riders USING GIST (default_pickup_location);",
            "DROP INDEX riders_default_pickup_location_idx;"
  end
end
