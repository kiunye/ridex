// Import user socket for real-time communication
import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"

// Make Phoenix Socket available globally for inline scripts
window.Phoenix = { Socket }
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

// Import hooks
let Hooks = {}

// Vehicle form hook to populate initial values
Hooks.VehicleForm = {
  mounted() {
    this.populateForm()
    this.setupModalHandlers()
  },
  
  updated() {
    this.populateForm()
  },
  
  populateForm() {
    const vehicleInfo = JSON.parse(this.el.dataset.vehicleInfo || '{}')
    const licensePlate = this.el.dataset.licensePlate || ''
    
    // Populate vehicle info fields
    const makeInput = this.el.querySelector('#vehicle_make')
    const modelInput = this.el.querySelector('#vehicle_model')
    const yearInput = this.el.querySelector('#vehicle_year')
    const colorInput = this.el.querySelector('#vehicle_color')
    const licensePlateInput = this.el.querySelector('#license_plate')
    
    if (makeInput && vehicleInfo.make) makeInput.value = vehicleInfo.make
    if (modelInput && vehicleInfo.model) modelInput.value = vehicleInfo.model
    if (yearInput && vehicleInfo.year) yearInput.value = vehicleInfo.year
    if (colorInput && vehicleInfo.color) colorInput.value = vehicleInfo.color
    if (licensePlateInput && licensePlate) licensePlateInput.value = licensePlate
  },
  
  setupModalHandlers() {
    // Handle backdrop clicks to close modal
    const backdrop = document.getElementById('vehicle-modal-backdrop')
    if (backdrop) {
      backdrop.addEventListener('click', (e) => {
        // Only close if clicking on the backdrop itself, not the modal content
        if (e.target === backdrop) {
          this.pushEvent('hide_vehicle_form', {})
        }
      })
    }
    
    // Prevent modal from closing when clicking inside the form
    this.el.addEventListener('click', (e) => {
      e.stopPropagation()
    })
  }
}

// Location handler hook for driver dashboard
Hooks.LocationHandler = {
  mounted() {
    this.handleEvent("request_location", () => {
      console.log("Location request received via hook");
      
      if (!navigator.geolocation) {
        console.log("Geolocation not supported");
        this.pushEvent("location_error", { error: "geolocation_not_supported" });
        return;
      }

      // Show loading state
      const enableButton = document.querySelector('button[phx-click="request_location"]');
      if (enableButton) {
        enableButton.disabled = true;
        enableButton.innerHTML = 'Getting Location...';
      }

      navigator.geolocation.getCurrentPosition(
        (position) => {
          console.log("Location received via hook:", position.coords);
          
          // Reset button state
          if (enableButton) {
            enableButton.disabled = false;
            enableButton.innerHTML = 'Enable Location';
          }
          
          // Send location data using hook's pushEvent
          this.pushEvent("location_received", {
            latitude: position.coords.latitude,
            longitude: position.coords.longitude,
            accuracy: position.coords.accuracy
          });
        },
        (error) => {
          console.error("Geolocation error via hook:", error);
          
          // Reset button state
          if (enableButton) {
            enableButton.disabled = false;
            enableButton.innerHTML = 'Retry';
          }
          
          let errorType;
          switch(error.code) {
            case error.PERMISSION_DENIED:
              errorType = "permission_denied";
              break;
            case error.POSITION_UNAVAILABLE:
              errorType = "position_unavailable";
              break;
            case error.TIMEOUT:
              errorType = "timeout";
              break;
            default:
              errorType = "unknown";
              break;
          }
          
          this.pushEvent("location_error", { error: errorType });
        },
        {
          enableHighAccuracy: true,
          timeout: 15000,
          maximumAge: 30000
        }
      );
    });
  }
}

// Location hook for getting user's current location
Hooks.LocationRequest = {
  mounted() {
    this.handleEvent("request_location", () => {
      if (navigator.geolocation) {
        navigator.geolocation.getCurrentPosition(
          (position) => {
            this.pushEvent("location_received", {
              latitude: position.coords.latitude,
              longitude: position.coords.longitude,
              accuracy: position.coords.accuracy
            })
          },
          (error) => {
            let errorType = "unknown"
            switch(error.code) {
              case error.PERMISSION_DENIED:
                errorType = "permission_denied"
                break
              case error.POSITION_UNAVAILABLE:
                errorType = "position_unavailable"
                break
              case error.TIMEOUT:
                errorType = "timeout"
                break
            }
            this.pushEvent("location_error", {error: errorType})
          },
          {
            enableHighAccuracy: true,
            timeout: 10000,
            maximumAge: 60000
          }
        )
      } else {
        this.pushEvent("location_error", {error: "geolocation_not_supported"})
      }
    })
  }
}

// Leaflet.js map hook for rider dashboard with OpenStreetMap
Hooks.RiderMap = {
  mounted() {
    console.debug("RiderMap mounted", { el: this.el });
    this.initMap()
    
    // Handle map events from LiveView
    this.handleEvent("update_map", (data) => {
      console.debug("RiderMap update_map", data);
      this.updateMap(data)
    })
    
    this.handleEvent("update_drivers", (data) => {
      console.debug("RiderMap update_drivers", data);
      this.updateDrivers(data.drivers)
    })
    
    this.handleEvent("set_pickup_marker", (location) => {
      console.debug("RiderMap set_pickup_marker", location);
      this.setPickupMarker(location)
    })
    
    this.handleEvent("set_destination_marker", (location) => {
      console.debug("RiderMap set_destination_marker", location);
      this.setDestinationMarker(location)
    })
    
    this.handleEvent("trip_accepted", (data) => {
      console.debug("RiderMap trip_accepted", data);
      this.showTripAccepted(data)
    })
    
    this.handleEvent("update_driver_location_in_trip", (data) => {
      console.debug("RiderMap update_driver_location_in_trip", data);
      this.updateDriverLocationInTrip(data)
    })
    
    this.handleEvent("trip_status_updated", (data) => {
      console.debug("RiderMap trip_status_updated", data);
      this.handleTripStatusUpdate(data)
    })
  },
  
  initMap() {
    console.debug("RiderMap initMap starting");
    // Initialize Leaflet map with OpenStreetMap tiles
    this.map = L.map(this.el, {
      center: [36.92280381917954, -1.2107287726962739], // Default to NYC
      zoom: 13,
      zoomControl: true
    })
    console.debug("RiderMap map created", this.map);
    
    // Add OpenStreetMap tile layer
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '© OpenStreetMap contributors'
    }).addTo(this.map)
    console.debug("RiderMap OSM tiles added");
    
    // Initialize marker layers
    this.driverMarkers = L.layerGroup().addTo(this.map)
    this.pickupMarker = null
    this.destinationMarker = null
    this.userMarker = null
    
    // Handle map clicks for setting pickup/destination
    this.map.on('click', (e) => {
      const lat = e.latlng.lat
      const lng = e.latlng.lng
      
      // Send click location to LiveView
      this.pushEvent("set_pickup_location", {
        latitude: lat,
        longitude: lng
      })
    })
    
    // Handle right-click for destination
    this.map.on('contextmenu', (e) => {
      const lat = e.latlng.lat
      const lng = e.latlng.lng
      
      this.pushEvent("set_destination", {
        latitude: lat,
        longitude: lng
      })
    })
  },
  
  updateMap(data) {
    if (data.latitude && data.longitude) {
      // Center map on user location
      this.map.setView([data.latitude, data.longitude], 15)
      
      // Add user location marker if not exists
      if (!this.userMarker) {
        this.userMarker = L.marker([data.latitude, data.longitude], {
          icon: L.divIcon({
            html: '<div class="w-4 h-4 bg-blue-500 rounded-full border-2 border-white shadow-lg"></div>',
            className: 'user-location-marker',
            iconSize: [16, 16],
            iconAnchor: [8, 8]
          })
        }).addTo(this.map).bindPopup('Your location')
      } else {
        this.userMarker.setLatLng([data.latitude, data.longitude])
      }
    }
    
    // Update drivers if provided
    if (data.drivers) {
      this.updateDrivers(data.drivers)
    }
  },
  
  updateDrivers(drivers) {
    // Clear existing driver markers
    this.driverMarkers.clearLayers()
    
    // Add new driver markers
    drivers.forEach(driver => {
      if (driver.current_location && driver.current_location.coordinates) {
        const [lng, lat] = driver.current_location.coordinates
        
        const driverIcon = L.divIcon({
          html: `
            <div class="driver-marker">
              <div class="w-8 h-8 bg-green-500 rounded-full border-2 border-white shadow-lg flex items-center justify-center">
                <svg class="w-4 h-4 text-white" fill="currentColor" viewBox="0 0 20 20">
                  <path d="M8 16.5a1.5 1.5 0 11-3 0 1.5 1.5 0 013 0zM15 16.5a1.5 1.5 0 11-3 0 1.5 1.5 0 013 0z"/>
                  <path d="M3 4a1 1 0 00-1 1v10a1 1 0 001 1h1.05a2.5 2.5 0 014.9 0H10a1 1 0 001-1V5a1 1 0 00-1-1H3zM14 7a1 1 0 00-1 1v6.05A2.5 2.5 0 0115.95 16H17a1 1 0 001-1V8a1 1 0 00-1-1h-3z"/>
                </svg>
              </div>
            </div>
          `,
          className: 'driver-marker-icon',
          iconSize: [32, 32],
          iconAnchor: [16, 16]
        })
        
        const marker = L.marker([lat, lng], { icon: driverIcon })
          .bindPopup(`
            <div>
              <strong>Available Driver</strong><br/>
              Vehicle: ${driver.vehicle_info?.make || 'Unknown'} ${driver.vehicle_info?.model || ''}<br/>
              Distance: ~${Math.round((driver.distance || 0) * 100) / 100} km away
            </div>
          `)
        
        this.driverMarkers.addLayer(marker)
      }
    })
  },
  
  setPickupMarker(location) {
    if (this.pickupMarker) {
      this.map.removeLayer(this.pickupMarker)
    }
    
    this.pickupMarker = L.marker([location.latitude, location.longitude], {
      icon: L.divIcon({
        html: `
          <div class="pickup-marker">
            <div class="w-6 h-6 bg-green-500 rounded-full border-2 border-white shadow-lg flex items-center justify-center">
              <div class="w-2 h-2 bg-white rounded-full"></div>
            </div>
          </div>
        `,
        className: 'pickup-marker-icon',
        iconSize: [24, 24],
        iconAnchor: [12, 12]
      })
    }).addTo(this.map).bindPopup('Pickup location')
  },
  
  setDestinationMarker(location) {
    if (this.destinationMarker) {
      this.map.removeLayer(this.destinationMarker)
    }
    
    this.destinationMarker = L.marker([location.latitude, location.longitude], {
      icon: L.divIcon({
        html: `
          <div class="destination-marker">
            <div class="w-6 h-6 bg-red-500 rounded-full border-2 border-white shadow-lg flex items-center justify-center">
              <div class="w-2 h-2 bg-white rounded-full"></div>
            </div>
          </div>
        `,
        className: 'destination-marker-icon',
        iconSize: [24, 24],
        iconAnchor: [12, 12]
      })
    }).addTo(this.map).bindPopup('Destination')
  },
  
  showTripAccepted(data) {
    // Clear existing driver markers and show only the assigned driver
    this.driverMarkers.clearLayers()
    
    // Add the assigned driver marker with special styling
    if (data.driver_info && data.driver_info.current_location) {
      const location = data.driver_info.current_location
      const driverIcon = L.divIcon({
        html: `
          <div class="assigned-driver-marker">
            <div class="w-10 h-10 bg-blue-600 rounded-full border-3 border-white shadow-lg flex items-center justify-center animate-pulse">
              <svg class="w-5 h-5 text-white" fill="currentColor" viewBox="0 0 20 20">
                <path d="M8 16.5a1.5 1.5 0 11-3 0 1.5 1.5 0 013 0zM15 16.5a1.5 1.5 0 11-3 0 1.5 1.5 0 013 0z"/>
                <path d="M3 4a1 1 0 00-1 1v10a1 1 0 001 1h1.05a2.5 2.5 0 014.9 0H10a1 1 0 001-1V5a1 1 0 00-1-1H3zM14 7a1 1 0 00-1 1v6.05A2.5 2.5 0 0115.95 16H17a1 1 0 001-1V8a1 1 0 00-1-1h-3z"/>
              </svg>
            </div>
          </div>
        `,
        className: 'assigned-driver-marker-icon',
        iconSize: [40, 40],
        iconAnchor: [20, 20]
      })
      
      this.assignedDriverMarker = L.marker([location.latitude, location.longitude], { icon: driverIcon })
        .bindPopup(`
          <div>
            <strong>Your Driver: ${data.driver_info.name || 'Driver'}</strong><br/>
            Vehicle: ${data.driver_info.vehicle_info?.make || 'Unknown'} ${data.driver_info.vehicle_info?.model || ''}<br/>
            License: ${data.driver_info.license_plate || 'N/A'}<br/>
            <span class="text-green-600 font-medium">En route to pickup</span>
          </div>
        `)
        .addTo(this.map)
    }
    
    // Center map to show both pickup location and driver
    if (this.pickupMarker && this.assignedDriverMarker) {
      const group = new L.featureGroup([this.pickupMarker, this.assignedDriverMarker])
      this.map.fitBounds(group.getBounds().pad(0.1))
    }
  },
  
  updateDriverLocationInTrip(data) {
    if (this.assignedDriverMarker) {
      // Update driver marker position
      this.assignedDriverMarker.setLatLng([data.latitude, data.longitude])
      
      // Update popup with estimated arrival if available
      if (data.estimated_arrival_minutes) {
        const popupContent = `
          <div>
            <strong>Your Driver</strong><br/>
            <span class="text-green-600 font-medium">En route to pickup</span><br/>
            <span class="text-sm text-gray-600">ETA: ~${data.estimated_arrival_minutes} minutes</span>
          </div>
        `
        this.assignedDriverMarker.setPopupContent(popupContent)
      }
    }
  },
  
  handleTripStatusUpdate(data) {
    if (this.assignedDriverMarker) {
      let statusText = "Unknown status"
      let statusColor = "text-gray-600"
      
      switch(data.status) {
        case "driver_arrived":
          statusText = "Driver has arrived!"
          statusColor = "text-green-600 font-bold"
          break
        case "in_progress":
          statusText = "Trip in progress"
          statusColor = "text-blue-600 font-medium"
          break
        case "completed":
          statusText = "Trip completed"
          statusColor = "text-gray-600"
          break
      }
      
      const popupContent = `
        <div>
          <strong>Your Driver</strong><br/>
          <span class="${statusColor}">${statusText}</span>
        </div>
      `
      this.assignedDriverMarker.setPopupContent(popupContent)
    }
  },
  
  destroyed() {
    if (this.map) {
      this.map.remove()
    }
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

