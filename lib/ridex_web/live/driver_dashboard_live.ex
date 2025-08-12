defmodule RidexWeb.DriverDashboardLive do
  @moduledoc """
  LiveView for driver dashboard with check-in/check-out functionality.
  """
  use RidexWeb, :live_view

  alias Ridex.Drivers

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    # Verify user is a driver
    case Drivers.get_driver_by_user_id(user.id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Access denied. Driver profile required.")
         |> redirect(to: ~p"/")}

      driver ->
        # Subscribe to location updates and ride requests for this user
        if connected?(socket) do
          RidexWeb.Endpoint.subscribe("location:user:#{user.id}")
          RidexWeb.Endpoint.subscribe("drivers:status")
          RidexWeb.Endpoint.subscribe("user:#{user.id}")
        end

        {:ok,
         socket
         |> assign(:driver, driver)
         |> assign(:location_permission, :unknown)
         |> assign(:current_location, nil)
         |> assign(:location_error, nil)
         |> assign(:checking_in, false)
         |> assign(:checking_out, false)
         |> assign(:ride_request, nil)
         |> assign(:request_timeout_ref, nil)
         |> assign(:accepting_trip, false)
         |> assign(:declining_trip, false)
         |> assign(:current_trip, nil)
         |> assign(:show_vehicle_form, false)
         |> assign(:vehicle_form, create_vehicle_form(driver))}
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
    lat = ensure_float(params["latitude"])
    lng = ensure_float(params["longitude"])
    accuracy = ensure_float(Map.get(params, "accuracy"))

    # Only proceed if we have valid latitude and longitude
    if lat && lng do
      {:noreply,
       socket
       |> assign(:current_location, %{latitude: lat, longitude: lng, accuracy: accuracy})
       |> assign(:location_permission, :granted)
       |> assign(:location_error, nil)}
    else
      {:noreply,
       socket
       |> assign(:location_permission, :denied)
       |> assign(:location_error, "Invalid location data received")}
    end
  end

  @impl true
  def handle_event("location_error", %{"error" => error}, socket) do
    error_message = case error do
      "permission_denied" -> "Location permission denied. Please enable location services."
      "position_unavailable" -> "Location unavailable. Please check your GPS settings."
      "timeout" -> "Location request timed out. Please try again."
      "geolocation_not_supported" -> "Geolocation is not supported by this browser."
      "invalid_coordinates" -> "Invalid location coordinates received. Please try again."
      _ -> "Unable to get location. Please try again."
    end

    {:noreply,
     socket
     |> assign(:location_permission, :denied)
     |> assign(:location_error, error_message)}
  end

  @impl true
  def handle_event("check_in", _params, socket) do
    %{current_location: location} = socket.assigns

    if location do
      {:noreply,
       socket
       |> assign(:checking_in, true)
       |> push_event("driver_checkin", %{
         latitude: location.latitude,
         longitude: location.longitude,
         accuracy: location.accuracy
       })}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Location required to check in. Please enable location services.")}
    end
  end

  @impl true
  def handle_event("check_out", _params, socket) do
    {:noreply,
     socket
     |> assign(:checking_out, true)
     |> push_event("driver_checkout", %{})}
  end

  @impl true
  def handle_event("checkin_success", _params, socket) do
    # Refresh driver data
    driver = Drivers.get_driver!(socket.assigns.driver.id)

    {:noreply,
     socket
     |> assign(:driver, driver)
     |> assign(:checking_in, false)
     |> put_flash(:info, "Successfully checked in! You are now available for rides.")}
  end

  @impl true
  def handle_event("checkin_error", %{"errors" => errors}, socket) do
    error_message = format_errors(errors)

    {:noreply,
     socket
     |> assign(:checking_in, false)
     |> put_flash(:error, "Check-in failed: #{error_message}")}
  end

  @impl true
  def handle_event("checkout_success", _params, socket) do
    # Refresh driver data
    driver = Drivers.get_driver!(socket.assigns.driver.id)

    {:noreply,
     socket
     |> assign(:driver, driver)
     |> assign(:checking_out, false)
     |> assign(:current_location, nil)
     |> put_flash(:info, "Successfully checked out. You are now offline.")}
  end

  @impl true
  def handle_event("checkout_error", %{"errors" => errors}, socket) do
    error_message = format_errors(errors)

    {:noreply,
     socket
     |> assign(:checking_out, false)
     |> put_flash(:error, "Check-out failed: #{error_message}")}
  end

  @impl true
  def handle_event("accept_ride_request", _params, socket) do
    case socket.assigns.ride_request do
      nil ->
        {:noreply, socket |> put_flash(:error, "No active ride request")}

      ride_request ->
        {:noreply,
         socket
         |> assign(:accepting_trip, true)
         |> push_event("accept_trip", %{trip_id: ride_request.trip_id})}
    end
  end

  @impl true
  def handle_event("decline_ride_request", _params, socket) do
    case socket.assigns.ride_request do
      nil ->
        {:noreply, socket |> put_flash(:error, "No active ride request")}

      ride_request ->
        {:noreply,
         socket
         |> assign(:declining_trip, true)
         |> push_event("decline_trip", %{trip_id: ride_request.trip_id})}
    end
  end

  @impl true
  def handle_event("trip_accepted", %{"trip" => trip_data}, socket) do
    # Clear ride request and set current trip
    socket = clear_ride_request_timeout(socket)

    {:noreply,
     socket
     |> assign(:ride_request, nil)
     |> assign(:accepting_trip, false)
     |> assign(:current_trip, trip_data)
     |> put_flash(:info, "Trip accepted! Navigate to pickup location.")}
  end

  @impl true
  def handle_event("trip_accept_error", %{"error" => error}, socket) do
    {:noreply,
     socket
     |> assign(:accepting_trip, false)
     |> put_flash(:error, "Failed to accept trip: #{error}")}
  end

  @impl true
  def handle_event("trip_declined", _params, socket) do
    # Clear ride request
    socket = clear_ride_request_timeout(socket)

    {:noreply,
     socket
     |> assign(:ride_request, nil)
     |> assign(:declining_trip, false)
     |> put_flash(:info, "Trip declined.")}
  end

  @impl true
  def handle_event("trip_decline_error", %{"error" => error}, socket) do
    {:noreply,
     socket
     |> assign(:declining_trip, false)
     |> put_flash(:error, "Failed to decline trip: #{error}")}
  end

  @impl true
  def handle_event("start_trip", _params, socket) do
    case socket.assigns.current_trip do
      nil ->
        {:noreply, socket |> put_flash(:error, "No active trip")}

      trip ->
        {:noreply, push_event(socket, "start_trip", %{trip_id: trip["id"]})}
    end
  end

  @impl true
  def handle_event("complete_trip", _params, socket) do
    case socket.assigns.current_trip do
      nil ->
        {:noreply, socket |> put_flash(:error, "No active trip")}

      trip ->
        {:noreply, push_event(socket, "complete_trip", %{trip_id: trip["id"]})}
    end
  end

  @impl true
  def handle_event("trip_started", %{"trip" => trip_data}, socket) do
    {:noreply,
     socket
     |> assign(:current_trip, trip_data)
     |> put_flash(:info, "Trip started!")}
  end

  @impl true
  def handle_event("trip_completed", %{"trip" => trip_data}, socket) do
    {:noreply,
     socket
     |> assign(:current_trip, nil)
     |> put_flash(:info, "Trip completed! Fare: $#{trip_data["fare"] || "0.00"}")}
  end

  @impl true
  def handle_event("trip_error", %{"error" => error}, socket) do
    {:noreply, socket |> put_flash(:error, "Trip error: #{error}")}
  end

  @impl true
  def handle_event("show_vehicle_form", _params, socket) do
    # Initialize form with current vehicle data
    form = create_vehicle_form(socket.assigns.driver)

    {:noreply,
     socket
     |> assign(:show_vehicle_form, true)
     |> assign(:vehicle_form, form)}
  end

  @impl true
  def handle_event("hide_vehicle_form", _params, socket) do
    {:noreply, assign(socket, :show_vehicle_form, false)}
  end



  @impl true
  def handle_event("validate_vehicle", %{"driver" => driver_params}, socket) do
    # Process vehicle_info to ensure proper data types
    processed_params = process_vehicle_params(driver_params)

    changeset =
      socket.assigns.driver
      |> Drivers.change_driver(processed_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :vehicle_form, to_form(changeset, as: "driver"))}
  end

  @impl true
  def handle_event("save_vehicle", %{"driver" => driver_params}, socket) do
    # Process vehicle_info to ensure proper data types
    processed_params = process_vehicle_params(driver_params)

    case Drivers.update_driver(socket.assigns.driver, processed_params) do
      {:ok, driver} ->
        {:noreply,
         socket
         |> assign(:driver, driver)
         |> assign(:show_vehicle_form, false)
         |> assign(:vehicle_form, create_vehicle_form(driver))
         |> put_flash(:info, "Vehicle information updated successfully!")}

      {:error, changeset} ->
        {:noreply, assign(socket, :vehicle_form, to_form(changeset, as: "driver"))}
    end
  end

  @impl true
  def handle_info(%{event: "location_updated", payload: location_data}, socket) do
    if location_data.user_id == socket.assigns.current_user.id do
      {:noreply,
       socket
       |> assign(:current_location, %{
         latitude: location_data.latitude,
         longitude: location_data.longitude,
         accuracy: location_data.accuracy
       })}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(%{event: "driver_status_changed", payload: status_data}, socket) do
    if status_data.user_id == socket.assigns.current_user.id do
      # Refresh driver data to get updated status
      driver = Drivers.get_driver!(socket.assigns.driver.id)
      {:noreply, assign(socket, :driver, driver)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:assign, key, value}, socket) do
    # Handle test assignments
    {:noreply, assign(socket, key, value)}
  end

  @impl true
  def handle_info(%{event: "ride_request", payload: request_data}, socket) do
    # Only show ride request if driver is active and doesn't have a current trip
    driver = socket.assigns.driver
    current_trip = socket.assigns.current_trip

    if driver.is_active and driver.availability_status == :active and is_nil(current_trip) do
      # Set up automatic timeout for the request
      timeout_ref = Process.send_after(self(), {:ride_request_timeout, request_data.trip_id}, 30_000)

      {:noreply,
       socket
       |> assign(:ride_request, request_data)
       |> assign(:request_timeout_ref, timeout_ref)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(%{event: "ride_request_cancelled", payload: _data}, socket) do
    # Clear any active ride request
    socket = clear_ride_request_timeout(socket)

    {:noreply,
     socket
     |> assign(:ride_request, nil)
     |> put_flash(:info, "Ride request was cancelled.")}
  end

  @impl true
  def handle_info(%{event: "trip_accepted", payload: trip_data}, socket) do
    # Update current trip if this driver accepted it
    if trip_data.driver_info && trip_data.driver_info["user_id"] == socket.assigns.current_user.id do
      {:noreply, assign(socket, :current_trip, trip_data)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(%{event: "trip_status_updated", payload: trip_data}, socket) do
    # Update current trip status
    if socket.assigns.current_trip && socket.assigns.current_trip["id"] == trip_data.trip_id do
      updated_trip = Map.put(socket.assigns.current_trip, "status", trip_data.status)
      {:noreply, assign(socket, :current_trip, updated_trip)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(%{event: "trip_cancelled", payload: trip_data}, socket) do
    # Clear current trip if it was cancelled
    if socket.assigns.current_trip && socket.assigns.current_trip["id"] == trip_data.trip_id do
      {:noreply,
       socket
       |> assign(:current_trip, nil)
       |> put_flash(:info, "Trip was cancelled: #{trip_data.reason}")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:ride_request_timeout, trip_id}, socket) do
    # Check if this timeout is for the current ride request
    case socket.assigns.ride_request do
      %{trip_id: ^trip_id} ->
        {:noreply,
         socket
         |> assign(:ride_request, nil)
         |> assign(:request_timeout_ref, nil)
         |> put_flash(:info, "Ride request expired.")}

      _ ->
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

  defp driver_status_class(driver) do
    case {driver.is_active, driver.availability_status} do
      {true, :active} -> "bg-green-100 text-green-800"
      {false, :offline} -> "bg-gray-100 text-gray-800"
      {_, :busy} -> "bg-yellow-100 text-yellow-800"
      {_, :away} -> "bg-blue-100 text-blue-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end

  defp driver_status_text(driver) do
    case {driver.is_active, driver.availability_status} do
      {true, :active} -> "Active - Available for rides"
      {false, :offline} -> "Offline"
      {_, :busy} -> "Busy"
      {_, :away} -> "Away"
      _ -> "Unknown"
    end
  end

  defp can_check_in?(driver, location) do
    not driver.is_active and
    not is_nil(location) and
    has_vehicle_info?(driver)
  end

  defp has_vehicle_info?(driver) do
    driver.vehicle_info != nil and
    driver.vehicle_info["make"] != nil and
    driver.vehicle_info["model"] != nil and
    driver.vehicle_info["year"] != nil and
    driver.license_plate != nil
  end

  defp can_check_out?(driver) do
    driver.is_active
  end

  defp clear_ride_request_timeout(socket) do
    case socket.assigns.request_timeout_ref do
      nil -> socket
      ref ->
        Process.cancel_timer(ref)
        assign(socket, :request_timeout_ref, nil)
    end
  end

  defp format_pickup_location(%{latitude: lat, longitude: lng}) do
    "#{Float.round(lat, 4)}, #{Float.round(lng, 4)}"
  end
  defp format_pickup_location(_), do: "Unknown location"

  defp trip_status_text(status) do
    case status do
      "requested" -> "Trip Requested"
      "accepted" -> "Trip Accepted - Navigate to Pickup"
      "in_progress" -> "Trip in Progress"
      "completed" -> "Trip Completed"
      "cancelled" -> "Trip Cancelled"
      _ -> "Unknown Status"
    end
  end

  defp trip_status_class(status) do
    case status do
      "requested" -> "bg-blue-100 text-blue-800"
      "accepted" -> "bg-yellow-100 text-yellow-800"
      "in_progress" -> "bg-green-100 text-green-800"
      "completed" -> "bg-gray-100 text-gray-800"
      "cancelled" -> "bg-red-100 text-red-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end

  defp can_start_trip?(trip) do
    trip && trip["status"] == "accepted"
  end

  defp can_complete_trip?(trip) do
    trip && trip["status"] == "in_progress"
  end



  defp should_show_ride_request?(driver, current_trip) do
    # Don't show ride requests if driver has a current trip
    if current_trip do
      false
    else
      # Don't show ride requests if driver is inactive
      driver.availability_status == :active
    end
  end

  # Helper function to process vehicle parameters
  defp process_vehicle_params(driver_params) do
    case Map.get(driver_params, "vehicle_info") do
      nil -> driver_params
      vehicle_info when is_map(vehicle_info) ->
        # Clean up vehicle_info - remove empty strings and convert year to integer
        cleaned_vehicle_info =
          vehicle_info
          |> Enum.reject(fn {_key, value} -> value == "" end)
          |> Enum.into(%{})
          |> convert_year_to_integer()

        # Only include vehicle_info if it has content
        if map_size(cleaned_vehicle_info) > 0 do
          Map.put(driver_params, "vehicle_info", cleaned_vehicle_info)
        else
          Map.delete(driver_params, "vehicle_info")
        end
      _ -> driver_params
    end
  end

  defp convert_year_to_integer(vehicle_info) do
    case Map.get(vehicle_info, "year") do
      year_str when is_binary(year_str) ->
        case Integer.parse(year_str) do
          {year_int, ""} -> Map.put(vehicle_info, "year", year_int)
          _ -> vehicle_info
        end
      _ -> vehicle_info
    end
  end

  # Helper function to create vehicle form with current data
  defp create_vehicle_form(driver) do
    # Create initial params with current vehicle data
    initial_params = %{
      "license_plate" => driver.license_plate || "",
      "vehicle_info" => driver.vehicle_info || %{}
    }

    changeset = Drivers.change_driver(driver, initial_params)
    to_form(changeset, as: "driver")
  end

  # Helper function to ensure a value is a float
  defp ensure_float(nil), do: nil
  defp ensure_float(value) when is_float(value), do: value
  defp ensure_float(value) when is_integer(value), do: value * 1.0
  defp ensure_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float_val, _} -> float_val
      :error -> nil
    end
  end
  defp ensure_float(_), do: nil
end
