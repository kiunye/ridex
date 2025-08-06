defmodule Ridex.AccountsFixtures do
  # @moduletag :reload
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ridex.Accounts` context.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "Hello123!"

  def valid_user_attributes(attrs \\ %{}) do
    attrs_map = Enum.into(attrs, %{})
    password = Map.get(attrs_map, :password, valid_user_password())

    Enum.into(attrs_map, %{
      email: unique_user_email(),
      name: "Test User",
      phone: "+1234567890",
      password: password,
      password_confirmation: password,
      role: "rider"
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Ridex.Accounts.create_user()

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end
