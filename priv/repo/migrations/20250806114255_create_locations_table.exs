defmodule Ridex.Repo.Migrations.CreateLocationsTable do
  use Ecto.Migration

  def change do
    create table(:locations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      add :latitude, :decimal, precision: 10, scale: 8, null: false
      add :longitude, :decimal, precision: 11, scale: 8, null: false
      add :accuracy, :decimal, precision: 8, scale: 2
      add :recorded_at, :utc_datetime, default: fragment("NOW()"), null: false

      timestamps()
    end

    create index(:locations, [:user_id, :recorded_at])
    create index(:locations, [:latitude, :longitude])
    create index(:locations, [:recorded_at])
  end
end
