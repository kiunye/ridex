defmodule Ridex.Repo.Migrations.CreateUsersTable do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :name, :string, null: false
      add :phone, :string
      add :password_hash, :string, null: false
      add :role, :string, null: false

      timestamps()
    end

    create unique_index(:users, [:email])
    create index(:users, [:role])
  end
end
