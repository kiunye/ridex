defmodule Ridex.LocationCleanupJob do
  @moduledoc """
  GenServer that periodically cleans up old location data for privacy compliance.
  Runs every 24 hours and removes location records older than 30 days.
  """
  use GenServer
  require Logger

  alias Ridex.Locations

  # Run cleanup every 24 hours (in milliseconds)
  @cleanup_interval 24 * 60 * 60 * 1000
  # Keep location data for 30 days
  @days_to_keep 30

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Schedule the first cleanup
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    perform_cleanup()
    schedule_cleanup()
    {:noreply, state}
  end

  @doc """
  Manually trigger a cleanup (useful for testing).
  """
  def trigger_cleanup do
    GenServer.cast(__MODULE__, :manual_cleanup)
  end

  @impl true
  def handle_cast(:manual_cleanup, state) do
    perform_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp perform_cleanup do
    Logger.info("Starting location data cleanup...")

    try do
      {deleted_count, _} = Locations.cleanup_old_locations(@days_to_keep)
      Logger.info("Location cleanup completed. Deleted #{deleted_count} old location records.")
    rescue
      error ->
        Logger.error("Location cleanup failed: #{inspect(error)}")
    end
  end
end
