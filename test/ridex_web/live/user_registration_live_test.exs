defmodule RidexWeb.UserRegistrationLiveTest do
  use RidexWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ridex.AccountsFixtures

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Register for Ridex"
      assert html =~ "Sign in"
    end

    test "redirects if already logged in", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:error, redirect} = live(conn, ~p"/users/register")

      assert {:redirect, %{to: path}} = redirect
      # User fixture creates a rider, so should redirect to rider dashboard
      assert path == ~p"/rider/dashboard"
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_submit(%{
          user: %{"email" => "with spaces", "password" => "too short", "role" => ""}
        })

      assert result =~ "must have the @ sign and no spaces"
      assert result =~ "at least one digit or punctuation character"
    end

    test "allows role selection via radio buttons", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      # Test selecting driver role
      html = render_click(lv, "select_role", %{"role" => "driver"})
      assert html =~ "Driver"
      assert html =~ "Rider"

      # Test selecting rider role
      html = render_click(lv, "select_role", %{"role" => "rider"})
      assert html =~ "Driver"
      assert html =~ "Rider"

      # Test that form submission includes the selected role
      html =
        lv
        |> form("#registration_form",
          user: %{
            "email" => "test@example.com",
            "name" => "Test User",
            "password" => "Hello123!",
            "password_confirmation" => "Hello123!",
            "phone" => "+1234567890"
          }
        )
        |> render_submit()

      # Should not have validation errors for role since it was selected
      refute html =~ "can't be blank"
    end
  end

  describe "register user" do
    test "creates account and logs the user in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()
      form = form(lv, "#registration_form", user: valid_user_attributes(email: email))
      render_submit(form)
      conn = follow_trigger_action(form, conn)

      # Default registration creates rider, so should redirect to rider dashboard
      assert redirected_to(conn) == ~p"/rider/dashboard"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ "Test User"
      assert response =~ "Log out"
    end

    test "renders errors for duplicated email", %{conn: conn} do
      %{email: email} = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> form("#registration_form", user: valid_user_attributes(email: email))
        |> render_submit()

      assert result =~ "has already been taken"
    end

    test "creates rider account with correct role", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      form =
        form(lv, "#registration_form", user: valid_user_attributes(email: email, role: "rider"))

      render_submit(form)
      conn = follow_trigger_action(form, conn)

      # Should redirect to rider dashboard for rider role
      assert redirected_to(conn) == ~p"/rider/dashboard"

      # Verify user was created with rider role
      user = Ridex.Accounts.get_user_by_email(email)
      assert user.role == :rider
    end

    test "creates driver account with correct role", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      form =
        form(lv, "#registration_form", user: valid_user_attributes(email: email, role: "driver"))

      render_submit(form)
      conn = follow_trigger_action(form, conn)

      # Should redirect to driver dashboard for driver role
      assert redirected_to(conn) == ~p"/driver/dashboard"

      # Verify user was created with driver role
      user = Ridex.Accounts.get_user_by_email(email)
      assert user.role == :driver
    end
  end
end
