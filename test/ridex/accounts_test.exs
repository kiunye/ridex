defmodule Ridex.AccountsTest do
  use Ridex.DataCase

  alias Ridex.Accounts

  describe "users" do
    alias Ridex.Accounts.User

    @invalid_attrs %{email: nil, name: nil, password: nil, role: nil}

    test "list_users/0 returns all users" do
      user = user_fixture()
      assert Accounts.list_users() == [user]
    end

    test "get_user!/1 returns the user with given id" do
      user = user_fixture()
      assert Accounts.get_user!(user.id) == user
    end

    test "get_user/1 returns the user with given id" do
      user = user_fixture()
      assert Accounts.get_user(user.id) == user
    end

    test "get_user/1 returns nil when user does not exist" do
      assert Accounts.get_user(Ecto.UUID.generate()) == nil
    end

    test "get_user_by_email/1 returns the user with given email" do
      user = user_fixture()
      assert Accounts.get_user_by_email(user.email) == user
    end

    test "get_user_by_email/1 returns nil when user does not exist" do
      assert Accounts.get_user_by_email("nonexistent@example.com") == nil
    end

    test "create_user/1 with valid data creates a user" do
      valid_attrs = %{
        email: "test@example.com",
        name: "Test User",
        phone: "+1234567890",
        password: "Password123!",
        password_confirmation: "Password123!",
        role: :rider
      }

      assert {:ok, %User{} = user} = Accounts.create_user(valid_attrs)
      assert user.email == "test@example.com"
      assert user.name == "Test User"
      assert user.phone == "+1234567890"
      assert user.role == :rider
      assert Bcrypt.verify_pass("Password123!", user.password_hash)
    end

    test "create_user/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Accounts.create_user(@invalid_attrs)
    end

    test "create_user/1 with duplicate email returns error changeset" do
      user_fixture(%{email: "duplicate@example.com"})
      
      attrs = %{
        email: "duplicate@example.com",
        name: "Another User",
        password: "Password123!",
        password_confirmation: "Password123!",
        role: :driver
      }

      assert {:error, changeset} = Accounts.create_user(attrs)
      assert "has already been taken" in errors_on(changeset).email
    end

    test "update_user/2 with valid data updates the user" do
      user = user_fixture()
      update_attrs = %{name: "Updated Name", phone: "+9876543210"}

      assert {:ok, %User{} = user} = Accounts.update_user(user, update_attrs)
      assert user.name == "Updated Name"
      assert user.phone == "+9876543210"
    end

    test "update_user/2 with invalid data returns error changeset" do
      user = user_fixture()
      assert {:error, %Ecto.Changeset{}} = Accounts.update_user(user, @invalid_attrs)
      assert user == Accounts.get_user!(user.id)
    end

    test "delete_user/1 deletes the user" do
      user = user_fixture()
      assert {:ok, %User{}} = Accounts.delete_user(user)
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_user!(user.id) end
    end

    test "change_user/1 returns a user changeset" do
      user = user_fixture()
      assert %Ecto.Changeset{} = Accounts.change_user(user)
    end

    test "change_user_registration/1 returns a user registration changeset" do
      assert %Ecto.Changeset{} = Accounts.change_user_registration()
    end
  end

  describe "authenticate_user/2" do
    test "authenticates user with valid credentials" do
      user = user_fixture(%{email: "auth@example.com", password: "Password123!"})
      
      assert {:ok, authenticated_user} = Accounts.authenticate_user("auth@example.com", "Password123!")
      assert authenticated_user.id == user.id
    end

    test "returns error with invalid password" do
      user_fixture(%{email: "auth@example.com", password: "Password123!"})
      
      assert {:error, :invalid_credentials} = Accounts.authenticate_user("auth@example.com", "WrongPassword")
    end

    test "returns error with non-existent email" do
      assert {:error, :invalid_credentials} = Accounts.authenticate_user("nonexistent@example.com", "Password123!")
    end

    test "returns error with empty email" do
      assert {:error, :invalid_credentials} = Accounts.authenticate_user("", "Password123!")
    end

    test "returns error with empty password" do
      user_fixture(%{email: "auth@example.com", password: "Password123!"})
      
      assert {:error, :invalid_credentials} = Accounts.authenticate_user("auth@example.com", "")
    end
  end
end