defmodule Ridex.LocationCleanupJobTest do
  use Ridex.DataCase

  alias Ridex.LocationCleanupJob
  alias Ridex.Locations

  import Ridex.AccountsFixtures

  describe "cleanup functionality" do
    test "removes old location records" do
      user = user_fixture()

      # Create old and recent locations
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      old_date = DateTime.add(now, -31 * 24 * 3600, :second)  # 31 days ago
      recent_date = DateTime.add(now, -10 * 24 * 3600, :second)  # 10 days ago

      {:ok, old_location} = Locations.create_location(%{
        user_id: user.id,
        latitude: Decimal.new("40.0"),
        longitude: Decimal.new("-74.0"),
        recorded_at: old_date
      })

      {:ok, recent_location} = Locations.create_location(%{
        user_id: user.id,
        latitude: Decimal.new("41.0"),
        longitude: Decimal.new("-75.0"),
        recorded_at: recent_date
      })

      # Trigger manual cleanup
      LocationCleanupJob.trigger_cleanup()

      # Give the GenServer time to process
      Process.sleep(100)

      # Check that old location is gone, recent location remains
      assert is_nil(Repo.get(Locations.Location, old_location.id))
      assert Repo.get(Locations.Location, recent_location.id)
    end

    test "handles cleanup errors gracefully" do
      # This test ensures the GenServer doesn't crash on errors
      # We can't easily simulate a database error in tests, but we can
      # verify the GenServer is still running after cleanup

      pid = Process.whereis(LocationCleanupJob)
      assert is_pid(pid)
      assert Process.alive?(pid)

      LocationCleanupJob.trigger_cleanup()
      Process.sleep(100)

      # GenServer should still be alive
      assert Process.alive?(pid)
    end
  end
end
