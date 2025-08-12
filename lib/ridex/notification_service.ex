defmodule Ridex.NotificationService do
  @moduledoc """
  Service for managing user notifications and broadcasting events
  """

  alias Ridex.Presence

  @doc """
  Send a notification to a specific user
  """
  def notify_user(user_id, notification) do
    Phoenix.PubSub.broadcast(
      Ridex.PubSub,
      "user:#{user_id}",
      {:user_notification, notification}
    )
  end

  @doc """
  Send a trip-related notification to a user
  """
  def notify_trip_event(user_id, trip_id, event, data \\ %{}) do
    Phoenix.PubSub.broadcast(
      Ridex.PubSub,
      "user:#{user_id}",
      {:trip_notification, trip_id, event, data}
    )
  end

  @doc """
  Broadcast a notification to all online users of a specific role
  """
  def broadcast_to_role(role, notification) when role in [:driver, :rider] do
    online_users = case role do
      :driver -> Presence.get_online_drivers()
      :rider -> Presence.get_online_riders()
    end

    Enum.each(online_users, fn {user_id, _meta} ->
      notify_user(user_id, notification)
    end)
  end

  @doc """
  Create a standardized notification structure
  """
  def create_notification(type, title, message, data \\ %{}) do
    %{
      id: generate_notification_id(),
      type: type,
      title: title,
      message: message,
      data: data,
      timestamp: System.system_time(:second),
      read: false
    }
  end

  @doc """
  Send a ride request notification to nearby drivers
  """
  def notify_ride_request(driver_ids, trip_id, pickup_location, rider_name) do
    notification = create_notification(
      "ride_request",
      "New Ride Request",
      "#{rider_name} is requesting a ride nearby",
      %{
        trip_id: trip_id,
        pickup_location: pickup_location,
        action_required: true,
        expires_at: System.system_time(:second) + 30 # 30 seconds to respond
      }
    )

    Enum.each(driver_ids, fn driver_id ->
      notify_user(driver_id, notification)
    end)
  end

  @doc """
  Send trip status update notifications
  """
  def notify_trip_status_change(trip, old_status, new_status) do
    case new_status do
      :accepted ->
        notify_user(trip.rider_id, create_notification(
          "trip_accepted",
          "Ride Accepted!",
          "Your driver is on the way to pick you up",
          %{trip_id: trip.id, driver_id: trip.driver_id}
        ))

      :in_progress ->
        notify_user(trip.rider_id, create_notification(
          "trip_started",
          "Trip Started",
          "Your ride has begun",
          %{trip_id: trip.id}
        ))

      :completed ->
        notify_user(trip.rider_id, create_notification(
          "trip_completed",
          "Trip Completed",
          "You have arrived at your destination",
          %{trip_id: trip.id, rating_required: true}
        ))

        notify_user(trip.driver_id, create_notification(
          "trip_completed",
          "Trip Completed",
          "Trip has been completed successfully",
          %{trip_id: trip.id}
        ))

      :cancelled ->
        if old_status == :requested do
          notify_user(trip.rider_id, create_notification(
            "trip_cancelled",
            "No Driver Found",
            "We couldn't find a driver for your request. Please try again.",
            %{trip_id: trip.id}
          ))
        else
          notify_user(trip.rider_id, create_notification(
            "trip_cancelled",
            "Trip Cancelled",
            "Your trip has been cancelled",
            %{trip_id: trip.id}
          ))

          if trip.driver_id do
            notify_user(trip.driver_id, create_notification(
              "trip_cancelled",
              "Trip Cancelled",
              "The trip has been cancelled",
              %{trip_id: trip.id}
            ))
          end
        end

      _ ->
        :ok
    end
  end

  @doc """
  Send driver status change notifications
  """
  def notify_driver_status_change(driver_id, _old_status, new_status) do
    case new_status do
      "active" ->
        notify_user(driver_id, create_notification(
          "status_change",
          "You're Online",
          "You are now active and can receive ride requests",
          %{status: new_status}
        ))

      "inactive" ->
        notify_user(driver_id, create_notification(
          "status_change",
          "You're Offline",
          "You are now offline and won't receive ride requests",
          %{status: new_status}
        ))

      _ ->
        :ok
    end
  end

  # Private helper to generate unique notification IDs
  defp generate_notification_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64()
  end
end
