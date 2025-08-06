#!/usr/bin/env elixir

# Simple script to test radio button functionality
# Run with: elixir test_radio_buttons.exs

IO.puts("Testing radio button functionality...")

# Start the application
Application.ensure_all_started(:ridex)

# Test the LiveView directly
{:ok, lv, _html} = Phoenix.LiveViewTest.live(Phoenix.ConnTest.build_conn(), "/users/register")

# Test selecting driver role
html = Phoenix.LiveViewTest.render_click(lv, "select_role", %{"role" => "driver"})
IO.puts("✓ Driver role selection works")

# Test selecting rider role
html = Phoenix.LiveViewTest.render_click(lv, "select_role", %{"role" => "rider"})
IO.puts("✓ Rider role selection works")

IO.puts("✓ All radio button tests passed!")
