# Script to create missing driver and rider profiles for existing users
alias Ridex.Repo
alias Ridex.Accounts.User
alias Ridex.Drivers
alias Ridex.Riders

import Ecto.Query

# Find all users without profiles
users_without_driver_profiles =
  from(u in User,
    left_join: d in assoc(u, :driver),
    where: u.role == :driver and is_nil(d.id),
    select: u
  )
  |> Repo.all()

users_without_rider_profiles =
  from(u in User,
    left_join: r in assoc(u, :rider),
    where: u.role == :rider and is_nil(r.id),
    select: u
  )
  |> Repo.all()

IO.puts("Found #{length(users_without_driver_profiles)} drivers without profiles")
IO.puts("Found #{length(users_without_rider_profiles)} riders without profiles")

# Create missing driver profiles
Enum.each(users_without_driver_profiles, fn user ->
  case Drivers.create_driver(%{user_id: user.id}) do
    {:ok, driver} ->
      IO.puts("Created driver profile for #{user.email}: #{driver.id}")
    {:error, changeset} ->
      IO.puts("Failed to create driver profile for #{user.email}: #{inspect(changeset.errors)}")
  end
end)

# Create missing rider profiles
Enum.each(users_without_rider_profiles, fn user ->
  case Riders.create_rider(%{user_id: user.id}) do
    {:ok, rider} ->
      IO.puts("Created rider profile for #{user.email}: #{rider.id}")
    {:error, changeset} ->
      IO.puts("Failed to create rider profile for #{user.email}: #{inspect(changeset.errors)}")
  end
end)

IO.puts("Profile creation complete!")
