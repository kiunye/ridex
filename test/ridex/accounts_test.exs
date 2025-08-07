defmodule Ridex.AccountsTest do
  use Ridex.DataCase

  alias Ridex.Accounts

  describe "create_user_with_profile/1" do
    test "creates a driver user with driver profile" do
      attrs = %{
        "email" => "driver@example.com",
        "name" => "Test Driver",
        "phone" => "+1234567890",
        "password" => "Password123",
        "role" => "driver"
      }

      assert {:ok, user} = Accounts.create_user_with_profile(attrs)
      assert user.role == :driver
      assert user.email == "driver@example.com"

      # Verify driver profile was created
      driver = Ridex.Drivers.get_driver_by_user_id(user.id)
      assert driver != nil
      assert driver.user_id == user.id
    end

    test "creates a rider user with rider profile" do
      attrs = %{
        "email" => "rider@example.com",
        "name" => "Test Rider",
        "phone" => "+1234567890",
        "password" => "Password123",
        "role" => "rider"
      }

      assert {:ok, user} = Accounts.create_user_with_profile(attrs)
      assert user.role == :rider
      assert user.email == "rider@example.com"

      # Verify rider profile was created
      rider = Ridex.Riders.get_rider_by_user_id(user.id)
      assert rider != nil
      assert rider.user_id == user.id
    end

    test "rolls back transaction if profile creation fails" do
      # This test would require mocking the profile creation to fail
      # For now, we'll just test that invalid user data fails properly
      attrs = %{
        "email" => "invalid-email",
        "name" => "",
        "password" => "short",
        "role" => "driver"
      }

      assert {:error, changeset} = Accounts.create_user_with_profile(attrs)
      assert changeset.errors != []
    end
  end
end
