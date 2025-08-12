// Bring in Phoenix channels client library:
import {Socket, Presence} from "phoenix"

// Create socket connection with user token for authentication
let socket = new Socket("/socket", {params: {token: window.userToken}})

// Global variables for channels and presence
let userChannel = null
let lobbyChannel = null
let presences = {}

// Connect to socket
socket.connect()

// Initialize presence tracking if user is authenticated
if (window.userToken && window.currentUserId) {
  initializePresenceTracking()
}

function initializePresenceTracking() {
  // Join user's personal channel for notifications
  userChannel = socket.channel(`user:${window.currentUserId}`, {})
  
  userChannel.join()
    .receive("ok", resp => { 
      console.log("Joined user channel successfully", resp) 
    })
    .receive("error", resp => { 
      console.log("Unable to join user channel", resp) 
    })

  // Handle user notifications
  userChannel.on("notification", (notification) => {
    showNotification(notification)
  })

  // Handle trip notifications
  userChannel.on("trip_notification", (data) => {
    showTripNotification(data)
  })

  // Handle presence updates
  userChannel.on("presence_update", (update) => {
    handlePresenceUpdate(update)
  })

  // Join lobby channel to track all online users
  lobbyChannel = socket.channel("users:lobby", {})
  
  lobbyChannel.join()
    .receive("ok", resp => { 
      console.log("Joined lobby channel successfully", resp) 
    })
    .receive("error", resp => { 
      console.log("Unable to join lobby channel", resp) 
    })

  // Track presence changes in lobby
  lobbyChannel.on("presence_state", state => {
    presences = Presence.syncState(presences, state)
    updateOnlineUsersList()
  })

  lobbyChannel.on("presence_diff", diff => {
    presences = Presence.syncDiff(presences, diff)
    updateOnlineUsersList()
  })

  // Send periodic ping to keep connection alive
  setInterval(() => {
    if (userChannel) {
      userChannel.push("ping", {})
    }
  }, 30000) // Every 30 seconds

  // Handle page visibility changes to update status
  document.addEventListener('visibilitychange', () => {
    if (userChannel) {
      const status = document.hidden ? 'away' : 'online'
      userChannel.push("status_update", {status: status})
    }
  })

  // Update status to online when page loads
  window.addEventListener('load', () => {
    if (userChannel) {
      userChannel.push("status_update", {status: 'online'})
    }
  })

  // Update status to offline when page unloads
  window.addEventListener('beforeunload', () => {
    if (userChannel) {
      userChannel.push("status_update", {status: 'offline'})
    }
  })
}

function showNotification(notification) {
  // Create notification element
  const notificationEl = document.createElement('div')
  notificationEl.className = `
    fixed top-4 right-4 z-50 max-w-sm w-full bg-white rounded-lg shadow-lg border border-gray-200 p-4
    transform transition-all duration-300 ease-in-out translate-x-full
  `
  
  // Determine notification styling based on type
  let iconColor = 'text-blue-500'
  let borderColor = 'border-blue-200'
  
  switch(notification.type) {
    case 'ride_request':
      iconColor = 'text-green-500'
      borderColor = 'border-green-200'
      break
    case 'trip_accepted':
      iconColor = 'text-green-500'
      borderColor = 'border-green-200'
      break
    case 'trip_cancelled':
      iconColor = 'text-red-500'
      borderColor = 'border-red-200'
      break
    case 'trip_completed':
      iconColor = 'text-blue-500'
      borderColor = 'border-blue-200'
      break
  }
  
  notificationEl.innerHTML = `
    <div class="flex items-start">
      <div class="flex-shrink-0">
        <svg class="w-6 h-6 ${iconColor}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
      </div>
      <div class="ml-3 w-0 flex-1">
        <p class="text-sm font-medium text-gray-900">${notification.title}</p>
        <p class="mt-1 text-sm text-gray-500">${notification.message}</p>
        ${notification.data.action_required ? `
          <div class="mt-3 flex space-x-2">
            <button onclick="handleNotificationAction('${notification.id}', 'accept')" 
                    class="text-xs bg-green-600 text-white px-3 py-1 rounded hover:bg-green-700">
              Accept
            </button>
            <button onclick="handleNotificationAction('${notification.id}', 'decline')" 
                    class="text-xs bg-red-600 text-white px-3 py-1 rounded hover:bg-red-700">
              Decline
            </button>
          </div>
        ` : ''}
      </div>
      <div class="ml-4 flex-shrink-0 flex">
        <button onclick="this.parentElement.parentElement.parentElement.remove()" 
                class="text-gray-400 hover:text-gray-600">
          <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd"></path>
          </svg>
        </button>
      </div>
    </div>
  `
  
  // Add to page
  document.body.appendChild(notificationEl)
  
  // Animate in
  setTimeout(() => {
    notificationEl.classList.remove('translate-x-full')
  }, 100)
  
  // Auto-remove after 5 seconds (unless action required)
  if (!notification.data.action_required) {
    setTimeout(() => {
      notificationEl.classList.add('translate-x-full')
      setTimeout(() => notificationEl.remove(), 300)
    }, 5000)
  }
}

function showTripNotification(data) {
  // Show trip-specific notifications
  const notification = {
    id: `trip_${data.trip_id}_${Date.now()}`,
    title: getTripNotificationTitle(data.event),
    message: getTripNotificationMessage(data.event, data.data),
    type: data.event,
    data: data.data || {}
  }
  
  showNotification(notification)
}

function getTripNotificationTitle(event) {
  switch(event) {
    case 'trip_accepted': return 'Ride Accepted!'
    case 'driver_arrived': return 'Driver Arrived'
    case 'trip_started': return 'Trip Started'
    case 'trip_completed': return 'Trip Completed'
    case 'trip_cancelled': return 'Trip Cancelled'
    default: return 'Trip Update'
  }
}

function getTripNotificationMessage(event, data) {
  switch(event) {
    case 'trip_accepted': return 'Your driver is on the way to pick you up'
    case 'driver_arrived': return 'Your driver has arrived at the pickup location'
    case 'trip_started': return 'Your trip has begun'
    case 'trip_completed': return 'You have arrived at your destination'
    case 'trip_cancelled': return 'Your trip has been cancelled'
    default: return 'Your trip status has been updated'
  }
}

function handlePresenceUpdate(update) {
  console.log('Presence update:', update)
  // Handle presence updates (user online/offline, status changes)
  // This can be used to update UI elements showing user status
}

function updateOnlineUsersList() {
  // Update any UI elements that show online users
  const onlineUsers = Presence.list(presences, (id, {metas: [first, ...rest]}) => {
    return {
      id: id,
      name: first.name,
      role: first.role,
      status: first.status,
      joined_at: first.joined_at
    }
  })
  
  console.log('Online users:', onlineUsers)
  
  // Dispatch custom event for LiveViews to handle
  window.dispatchEvent(new CustomEvent('presence:online_users_updated', {
    detail: {users: onlineUsers}
  }))
}

// Global function to handle notification actions
window.handleNotificationAction = function(notificationId, action) {
  console.log(`Notification ${notificationId} action: ${action}`)
  
  // Send action to appropriate channel
  if (userChannel) {
    userChannel.push("notification_action", {
      notification_id: notificationId,
      action: action
    })
  }
  
  // Remove notification
  const notificationEl = document.querySelector(`[data-notification-id="${notificationId}"]`)
  if (notificationEl) {
    notificationEl.remove()
  }
}

// Export socket and channels for use in other modules
export default socket
export { userChannel, lobbyChannel, presences }