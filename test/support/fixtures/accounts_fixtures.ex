defmodule Ridex.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ridex.Accounts` context.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def unique_user_phone, do: "+1#{System.unique_integer([:positive]) |> Integer.to_string() |> String.pad_leading(10, "0")}"

  def valid_user_password, do: "Password123!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      name: "Test User",
      phone: unique_user_phone(),
      password: valid_user_password(),
      password_confirmation: valid_user_password(),
      role: :rider
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Ridex.Accounts.create_user()

    user
  end

  def driver_user_fixture(attrs \\ %{}) do
    attrs
    |> Map.put(:role, :driver)
    |> user_fixture()
  end

  def rider_user_fixture(attrs \\ %{}) do
    attrs
    |> Map.put(:role, :rider)
    |> user_fixture()
  end
end