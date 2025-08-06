# Ridex

Real-time is everywhere now. It doesn’t matter which kind of application you want to build — a chat, a shared documents service like Google Docs, a social mobile app with push notifications, a live game, or a live news feed, real-time features are more and more needed in modern applications.

Elixir/OTP is a really good platform whenever you want to build backend systems with real-time features, thanks to the Erlang VM foundations. A famous example of applications using such real-time features are ride-sharing applications like Uber or Lyft. A driver checks in on his phone, and riders can request for a ride, before being — hopefully — matched with the closest driver, everything happening in real-time, sometimes in a matter of seconds.

Ridex is a simple prototype for a ride sharing application with Elixir and the Phoenix framework, using some of its real-time communication features like Channels and Presence. For the sake of simplicity, it's a basic web app, allowing users to check in and share their current location, and riders to request for a ride. The web app will contain a map with real-time positions of drivers operating in the area.

## Prerequisites

- Elixir 1.14+
- Docker and Docker Compose
- Node.js (for asset compilation)

## Setup

1. Install dependencies:

   ```bash
   mix deps.get
   ```

2. Start PostgreSQL with PostGIS using Docker:

   ```bash
   docker-compose up -d
   ```

3. Set up the database:

   ```bash
   mix ecto.setup
   ```

4. Install Node.js dependencies and build assets:

   ```bash
   mix assets.setup
   mix assets.build
   ```

5. Start the Phoenix server:
   ```bash
   mix phx.server
   ```

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Key Dependencies

- **Phoenix LiveView**: Real-time user interface
- **PostgreSQL + PostGIS**: Database with geospatial support
- **Phoenix Presence**: Real-time user presence tracking
- **Bcrypt**: Password hashing
- **TailwindCSS**: Styling framework
- **ExMachina**: Test data factories

## Database

The application uses PostgreSQL with PostGIS extension for geospatial data. The database runs in a Docker container for easy setup and consistent development environment.

## Testing

Run the test suite:

```bash
mix test
```


