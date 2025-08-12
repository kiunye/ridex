defmodule RidexWeb.RiderDashboardLive do
  @moduledoc """
  LiveView for rider dashboard with map interface and ride request functionality.
  """
  use RidexWeb, :live_view

  alias Ridex.Riders
  alias Ridex.LocationService
  alias Ridex.MatchingService

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    # Verify user is a rider or create rider profile if needed
    rider = case Riders.get_rider_by_user_id(user.id) do
      nil ->
        # Auto-create rider profile for users with rider role
        if user.role == :rider do
          case Riders.create_rider(%{user_id: user.id}) do
            {:ok, rider} -> rider
            {:error, _} -> nil
          end
        else
          nil
        end
      rider ->
        rider
    end

    case rider do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Access denied. Rider profile required.")
         |> redirect(to: ~p"/")}

      rider ->
        # Subscribe to location updates and trip notifications
        if connected?(socket) do
          RidexWeb.Endpoint.subscribe("location:updates")
          RidexWeb.Endpoint.subscribe("drivers:locations")
          RidexWeb.Endpoint.subscribe("user:#{user.id}")
        end

        {:ok,
         socket
         |> assign(:rider, rider)
         |> assign(:current_location, nil)
         |> assign(:location_permission, :unknown)
         |> assign(:location_error, nil)
         |> assign(:nearby_drivers, [])
         |> assign(:pickup_location, nil)
         |> assign(:destination, nil)
         |> assign(:requesting_ride, false)
         |> assign(:current_trip, nil)
         |> assign(:trip_search_status, nil)
         |> assign(:map_center, %{latitude: 37.7749, longitude: -122.4194}) # Default to SF
         |> assign(:map_zoom, 13)}
    end
  end

  @impl true
  def handle_event("request_location", _params, socket) do
    {:noreply,
     socket
     |> push_event("request_location", %{})}
  end

  @impl true
  def handle_event("location_received", params, socket) do
    lat = params["latitude"]
    lng = params["longitude"]
    accuracy = Map.get(params, "accuracy")

    location = %{latitude: lat, longitude: lng, accuracy: accuracy}

    # Update location service
    LocationService.update_location(socket.assigns.current_user.id, lat, lng, accuracy)

    # Get nearby drivers
    nearby_drivers = LocationService.get_nearby_drivers(lat, lng, 10.0)

    {:noreply,
     socket
     |> assign(:current_location, location)
     |> assign(:location_permission, :granted)
     |> assign(:location_error, nil)
     |> assign(:nearby_drivers, nearby_drivers)
     |> assign(:map_center, %{latitude: lat, longitude: lng})
     |> push_event("update_map", %{
       latitude: lat,
       longitude: lng,
       zoom: 15,
       drivers: nearby_drivers
     })}
  end

  @impl true
  def handle_event("location_error", %{"error" => error}, socket) do
    error_message = case error do
      "permission_denied" -> "Location permission denied. Please enable location services to see nearby drivers."
      "position_unavailable" -> "Location unavailable. Please check your GPS settings."
      "timeout" -> "Location request timed out. Please try again."
      _ -> "Unable to get location. Please try again."
    end

    {:noreply,
     socket
     |> assign(:location_permission, :denied)
     |> assign(:location_error, error_message)}
  end

  @impl true
  def handle_event("set_pickup_location", %{"latitude" => lat, "longitude" => lng}, socket) do
    pickup_location = %{latitude: lat, longitude: lng}

    {:noreply,
     socket
     |> assign(:pickup_location, pickup_location)
     |> push_event("set_pickup_marker", pickup_location)}
  end

  @impl true
  def handle_event("set_destination", %{"latitude" => lat, "longitude" => lng}, socket) do
    destination = %{latitude: lat, longitude: lng}

    {:noreply,
     socket
     |> assign(:destination, destination)
     |> push_event("set_destination_marker", destination)}
  end

  @impl true
  def handle_event("request_ride", _params, socket) do
    %{pickup_location: pickup_location, rider: rider} = socket.assigns

    case validate_ride_request(pickup_location, socket.assigns) do
      {:error, message} ->
        {:noreply, socket |> put_flash(:error, message)}

      :ok ->
        %{latitude: lat, longitude: lng} = pickup_location
        pickup_point = %Geo.Point{coordinates: {lng, lat}, srid: 4326}
        destination_point = case socket.assigns.destination do
          %{latitude: dest_lat, longitude: dest_lng} ->
            %Geo.Point{coordinates: {dest_lng, dest_lat}, srid: 4326}
          _ -> nil
        end

        trip_attrs = %{
          rider_id: rider.user_id,  # Use user_id for TripService
          pickup_location: pickup_point,
          destination: destination_point
        }

        case Ridex.Trips.TripService.create_trip_request(trip_attrs) do
          {:ok, trip} ->
            # Start matching process with enhanced feedback
            case MatchingService.notify_drivers_of_request(trip.id, pickup_point) do
              {:ok, result} ->
                drivers_count = length(result.drivers)
                search_status = "Found #{drivers_count} nearby drivers. Waiting for responses..."

                # Schedule automatic timeout
                Process.send_after(self(), {:trip_request_timeout, trip.id}, 120_000) # 2 minutes

                {:noreply,
                 socket
                 |> assign(:requesting_ride, true)
                 |> assign(:current_trip, %{trip | driver: nil})
                 |> assign(:trip_search_status, search_status)
                 |> assign(:search_start_time, DateTime.utc_now())
                 |> put_flash(:info, "Ride requested! #{search_status}")}

              {:error, :no_drivers_available} ->
                # Cancel the trip since no drivers are available
                Ridex.Trips.TripService.cancel_trip(trip.id, rider.user_id, "No drivers available", :rider)

                {:noreply,
                 socket
                 |> put_flash(:error, "No drivers available in your area. Please try again later.")
                 |> assign(:requesting_ride, false)}

              {:error, reason} ->
                # Cancel the trip due to notification failure
                Ridex.Trips.TripService.cancel_trip(trip.id, rider.user_id, "System error: #{reason}", :rider)

                {:noreply,
                 socket
                 |> put_flash(:error, "Failed to notify drivers. Please try again.")
                 |> assign(:requesting_ride, false)}
            end

          {:error, :too_many_active_trips} ->
            {:noreply,
             socket
             |> put_flash(:error, "You have too many active trip requests. Please wait for them to complete.")}

          {:error, reason} ->
            error_message = format_trip_service_error(reason)

            {:noreply,
             socket
             |> put_flash(:error, "Failed to request ride: #{error_message}")}
        end
    end
  end

  @impl true
  def handle_event("cancel_ride_request", _params, socket) do
    case socket.assigns.current_trip do
      nil ->
        {:noreply, socket}

      trip ->
        rider = socket.assigns.rider
        case Ridex.Trips.TripService.cancel_trip(trip.id, rider.user_id, "Cancelled by rider", :rider) do
          {:ok, _cancelled_trip} ->
            # Broadcast cancellation to any listening drivers
            RidexWeb.Endpoint.broadcast("trip:#{trip.id}", "trip_cancelled", %{
              trip_id: trip.id,
              reason: "Cancelled by rider",
              cancelled_by: :rider
            })

            {:noreply,
             socket
             |> assign(:requesting_ride, false)
             |> assign(:current_trip, nil)
             |> assign(:trip_search_status, nil)
             |> assign(:search_start_time, nil)
             |> put_flash(:info, "Ride request cancelled.")}

          {:error, :not_authorized_to_cancel} ->
            {:noreply,
             socket
             |> put_flash(:error, "You cannot cancel this trip at this time.")}

          {:error, _reason} ->
            {:noreply,
             socket
             |> put_flash(:error, "Failed to cancel ride request. Please try again.")}
        end
    end
  end

  @impl true
  def handle_event("refresh_drivers", _params, socket) do
    case socket.assigns.current_location do
      %{latitude: lat, longitude: lng} ->
        nearby_drivers = LocationService.get_nearby_drivers(lat, lng, 10.0)

        {:noreply,
         socket
         |> assign(:nearby_drivers, nearby_drivers)
         |> push_event("update_drivers", %{drivers: nearby_drivers})}

      _ ->
        {:noreply, socket}
    end
  end

  # Handle real-time updates

  @impl true
  def handle_info(%{event: "driver_location_updated", payload: location_data}, socket) do
    current_trip = socket.assigns.current_trip

    # If we have an active trip and this is our driver's location, update the map
    if current_trip && current_trip.driver &&
       current_trip.driver["user_id"] == location_data.user_id do

      # Calculate estimated arrival time if driver is en route
      estimated_arrival = if current_trip.status == :accepted do
        calculate_estimated_arrival(location_data, socket.assigns.pickup_location)
      else
        nil
      end

      {:noreply,
       socket
       |> push_event("update_driver_location_in_trip", %{
         location_data | estimated_arrival_minutes: estimated_arrival
       })}
    else
      # Update the driver's position on the map if they're in our nearby list
      updated_drivers = update_driver_in_list(socket.assigns.nearby_drivers, location_data)

      {:noreply,
       socket
       |> assign(:nearby_drivers, updated_drivers)
       |> push_event("update_driver_location", location_data)}
    end
  end

  @impl true
  def handle_info(%{event: "driver_status_changed", payload: _status_data}, socket) do
    # Refresh nearby drivers list when driver status changes
    case socket.assigns.current_location do
      %{latitude: lat, longitude: lng} ->
        nearby_drivers = LocationService.get_nearby_drivers(lat, lng, 10.0)

        {:noreply,
         socket
         |> assign(:nearby_drivers, nearby_drivers)
         |> push_event("update_drivers", %{drivers: nearby_drivers})}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(%{event: "trip_accepted", payload: trip_data}, socket) do
    # Check if this is our trip
    current_trip = socket.assigns.current_trip

    if current_trip && current_trip.id == trip_data.trip_id do
      # Subscribe to trip-specific channel for real-time updates
      RidexWeb.Endpoint.subscribe("trip:#{trip_data.trip_id}")

      driver_name = get_in(trip_data, [:driver_info, "name"]) || "Your driver"

      updated_trip = Map.merge(current_trip, %{
        status: :accepted,
        driver: trip_data.driver_info,
        accepted_at: trip_data.accepted_at || DateTime.utc_now()
      })

      {:noreply,
       socket
       |> assign(:requesting_ride, false)
       |> assign(:current_trip, updated_trip)
       |> assign(:trip_search_status, nil)
       |> assign(:search_start_time, nil)
       |> put_flash(:info, "Driver found! #{driver_name} is heading to your location.")
       |> push_event("trip_accepted", %{
         trip: updated_trip,
         driver_info: trip_data.driver_info
       })}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(%{event: "trip_status_updated", payload: trip_data}, socket) do
    current_trip = socket.assigns.current_trip

    if current_trip && current_trip.id == trip_data.trip_id do
      new_status = String.to_atom(trip_data.status)
      updated_trip = Map.put(current_trip, :status, new_status)

      {status_message, socket_updates} = case trip_data.status do
        "in_progress" ->
          {"Trip started! You're on your way.", []}
        "completed" ->
          {"Trip completed! Thanks for riding with us.", [
            assign(:current_trip, nil),
            assign(:requesting_ride, false),
            assign(:trip_search_status, nil)
          ]}
        "driver_arrived" ->
          {"Your driver has arrived at the pickup location!", []}
        _ ->
          {nil, []}
      end

      socket = socket
      |> assign(:current_trip, updated_trip)
      |> then(fn s ->
        if status_message, do: put_flash(s, :info, status_message), else: s
      end)
      |> then(fn s ->
        Enum.reduce(socket_updates, s, fn update_fn, acc -> update_fn.(acc) end)
      end)
      |> push_event("trip_status_updated", %{
        trip_id: trip_data.trip_id,
        status: trip_data.status,
        timestamp: trip_data.timestamp || DateTime.utc_now()
      })

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(%{event: "trip_cancelled", payload: trip_data}, socket) do
    current_trip = socket.assigns.current_trip

    if current_trip && current_trip.id == trip_data.trip_id do
      {:noreply,
       socket
       |> assign(:requesting_ride, false)
       |> assign(:current_trip, nil)
       |> assign(:trip_search_status, nil)
       |> put_flash(:info, "Trip was cancelled: #{trip_data.reason}")}
    else
      {:noreply, socket}
    end
  end



  @impl true
  def handle_info({:trip_request_timeout, trip_id}, socket) do
    current_trip = socket.assigns.current_trip

    # Only handle timeout if this is still our active trip and it's still in requested status
    if current_trip && current_trip.id == trip_id && current_trip.status == :requested do
      rider = socket.assigns.rider

      # Cancel the expired trip
      case Ridex.Trips.TripService.cancel_trip(trip_id, rider.user_id, "Request timeout - no drivers responded", :rider) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:requesting_ride, false)
           |> assign(:current_trip, nil)
           |> assign(:trip_search_status, nil)
           |> assign(:search_start_time, nil)
           |> put_flash(:error, "No drivers responded to your request. Please try again.")}

        {:error, _} ->
          # Trip might have been accepted in the meantime, just clear our state
          {:noreply,
           socket
           |> assign(:requesting_ride, false)
           |> assign(:trip_search_status, nil)}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Helper functions

  defp format_errors(errors) when is_map(errors) do
    errors
    |> Enum.map(fn {field, messages} ->
      "#{field}: #{Enum.join(messages, ", ")}"
    end)
    |> Enum.join("; ")
  end

  defp format_errors(errors) when is_binary(errors), do: errors
  defp format_errors(_), do: "Unknown error occurred"

  defp format_trip_service_error(reason) do
    case reason do
      :rider_not_found -> "Rider profile not found"
      :too_many_active_trips -> "You have too many active trip requests"
      :invalid_pickup_location -> "Invalid pickup location"
      :invalid_destination -> "Invalid destination"
      :pickup_location_required -> "Pickup location is required"
      %Ecto.Changeset{} = changeset ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        format_errors(errors)
      _ when is_binary(reason) -> reason
      _ -> "An unexpected error occurred"
    end
  end

  defp update_driver_in_list(drivers, location_data) do
    Enum.map(drivers, fn driver ->
      if driver.user_id == location_data.user_id do
        %{driver |
          latitude: location_data.latitude,
          longitude: location_data.longitude,
          last_updated: location_data.recorded_at
        }
      else
        driver
      end
    end)
  end

  defp format_location(%{latitude: lat, longitude: lng}) do
    "#{Float.round(lat, 4)}, #{Float.round(lng, 4)}"
  end
  defp format_location(_), do: "Unknown location"

  defp trip_status_text(status) do
    case status do
      :requested -> "Searching for driver..."
      :accepted -> "Driver found - heading to pickup"
      :in_progress -> "Trip in progress"
      :completed -> "Trip completed"
      :cancelled -> "Trip cancelled"
      _ -> "Unknown status"
    end
  end

  defp trip_status_class(status) do
    case status do
      :requested -> "bg-blue-100 text-blue-800"
      :accepted -> "bg-yellow-100 text-yellow-800"
      :in_progress -> "bg-green-100 text-green-800"
      :completed -> "bg-gray-100 text-gray-800"
      :cancelled -> "bg-red-100 text-red-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end

  defp can_request_ride?(pickup_location, current_trip) do
    not is_nil(pickup_location) and is_nil(current_trip)
  end

  defp validate_ride_request(pickup_location, assigns) do
    cond do
      is_nil(pickup_location) ->
        {:error, "Please set a pickup location first."}

      not is_nil(assigns.current_trip) ->
        {:error, "You already have an active trip request."}

      assigns.location_permission != :granted ->
        {:error, "Location permission is required to request a ride."}

      length(assigns.nearby_drivers) == 0 ->
        {:error, "No drivers are currently available in your area."}

      true ->
        :ok
    end
  end

  defp calculate_estimated_arrival(location_data, pickup_location) do
    case pickup_location do
      %{latitude: pickup_lat, longitude: pickup_lng} ->
        distance_km = Ridex.LocationService.calculate_distance(
          location_data.latitude,
          location_data.longitude,
          pickup_lat,
          pickup_lng
        )
        # Assume average city speed of 25 km/h
        round(distance_km / 25.0 * 60)

      _ ->
        nil
    end
  end

  defp format_search_duration(start_time) do
    duration_seconds = DateTime.diff(DateTime.utc_now(), start_time, :second)

    cond do
      duration_seconds < 60 ->
        "#{duration_seconds}s"
      duration_seconds < 3600 ->
        minutes = div(duration_seconds, 60)
        seconds = rem(duration_seconds, 60)
        "#{minutes}m #{seconds}s"
      true ->
        "#{div(duration_seconds, 3600)}h"
    end
  end
end
