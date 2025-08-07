defmodule RidexWeb.TripController do
  @moduledoc """
  Controller for handling trip-related API requests.
  """
  use RidexWeb, :controller

  alias Ridex.Trips.TripService
  alias Ridex.MatchingService

  @doc """
  Accept a trip request.
  """
  def accept(conn, %{"id" => trip_id}) do
    current_user = conn.assigns[:current_user]

    case TripService.accept_trip(trip_id, current_user.id) do
      {:ok, trip} ->
        # Load trip with associations for response
        trip = Ridex.Repo.preload(trip, [driver: :user, rider: :user])

        trip_data = %{
          id: trip.id,
          status: trip.status,
          pickup_location: format_location(trip.pickup_location),
          destination: format_location(trip.destination),
          rider_info: format_rider_info(trip.rider),
          accepted_at: trip.accepted_at
        }

        json(conn, %{success: true, trip: trip_data})

      {:error, reason} ->
        error_message = case reason do
          :trip_not_found -> "Trip not found"
          :driver_not_found -> "Driver profile not found"
          :driver_not_active -> "Driver is not active"
          :driver_not_available -> "Driver is not available"
          :driver_has_active_trip -> "Driver already has an active trip"
          :trip_expired -> "Trip request has expired"
          {:trip_not_available, status} -> "Trip is no longer available (status: #{status})"
          _ -> "Unable to accept trip"
        end

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{success: false, error: error_message})
    end
  end

  @doc """
  Decline a trip request.
  """
  def decline(conn, %{"id" => trip_id}) do
    current_user = conn.assigns[:current_user]

    case MatchingService.handle_driver_response(trip_id, current_user.id, :decline) do
      {:ok, :trip_declined} ->
        json(conn, %{success: true})

      {:error, reason} ->
        error_message = case reason do
          :invalid_response -> "Invalid response"
          _ -> "Unable to decline trip"
        end

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{success: false, error: error_message})
    end
  end

  # Private helper functions

  defp format_location(%Geo.Point{coordinates: {lng, lat}}) do
    %{latitude: lat, longitude: lng}
  end
  defp format_location(_), do: nil

  defp format_rider_info(%{user: user}) when not is_nil(user) do
    %{
      id: user.id,
      name: user.name
    }
  end
  defp format_rider_info(_), do: nil
end
