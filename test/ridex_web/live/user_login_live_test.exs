defmodule RidexWeb.UserLoginLiveTest do
  use RidexWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ridex.AccountsFixtures

  describe "Log in page" do
    test "renders log in page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log_in")

      assert html =~ "Sign in to Ridex"
      assert html =~ "Sign up"
      assert html =~ "Keep me logged in"
    end

    test "redirects if already logged in", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:error, redirect} = live(conn, ~p"/users/log_in")

      assert {:redirect, %{to: path}} = redirect
      assert path == ~p"/"
    end
  end

  describe "user login" do
    test "redirects if user login with valid credentials", %{conn: conn} do
      password = valid_user_password()
      user = user_fixture(%{password: password})

      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      form =
        form(lv, "#login_form", user: %{email: user.email, password: password, remember_me: true})

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/"
    end

    test "redirects to intended page after login", %{conn: conn} do
      password = valid_user_password()
      user = user_fixture(%{password: password})

      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      form =
        form(lv, "#login_form", user: %{email: user.email, password: password})

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/"
    end

    test "displays error for invalid credentials", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      form =
        form(lv, "#login_form",
          user: %{email: "test@example.com", password: "invalid", remember_me: true}
        )

      conn = submit_form(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end
end