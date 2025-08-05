defmodule Ridex.Accounts.UserTest do
  use Ridex.DataCase

  alias Ridex.Accounts.User

  describe "changeset/2" do
    test "valid changeset" do
      attrs = %{
        email: "test@example.com",
        name: "Test User",
        phone: "+1234567890",
        role: :rider
      }

      changeset = User.changeset(%User{}, attrs)
      assert changeset.valid?
    end

    test "requires email" do
      attrs = %{name: "Test User", role: :rider}
      changeset = User.changeset(%User{}, attrs)
      
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).email
    end

    test "requires name" do
      attrs = %{email: "test@example.com", role: :rider}
      changeset = User.changeset(%User{}, attrs)
      
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "requires role" do
      attrs = %{email: "test@example.com", name: "Test User"}
      changeset = User.changeset(%User{}, attrs)
      
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).role
    end

    test "validates email format" do
      attrs = %{email: "invalid-email", name: "Test User", role: :rider}
      changeset = User.changeset(%User{}, attrs)
      
      refute changeset.valid?
      assert "must have the @ sign and no spaces" in errors_on(changeset).email
    end

    test "validates email with spaces" do
      attrs = %{email: "test @example.com", name: "Test User", role: :rider}
      changeset = User.changeset(%User{}, attrs)
      
      refute changeset.valid?
      assert "must have the @ sign and no spaces" in errors_on(changeset).email
    end

    test "validates email length" do
      long_email = String.duplicate("a", 150) <> "@example.com"
      attrs = %{email: long_email, name: "Test User", role: :rider}
      changeset = User.changeset(%User{}, attrs)
      
      refute changeset.valid?
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates phone format" do
      attrs = %{email: "test@example.com", name: "Test User", phone: "invalid", role: :rider}
      changeset = User.changeset(%User{}, attrs)
      
      refute changeset.valid?
      assert "must be a valid phone number" in errors_on(changeset).phone
    end

    test "validates phone length - too short" do
      attrs = %{email: "test@example.com", name: "Test User", phone: "123", role: :rider}
      changeset = User.changeset(%User{}, attrs)
      
      refute changeset.valid?
      assert "should be at least 10 character(s)" in errors_on(changeset).phone
    end

    test "validates phone length - too long" do
      long_phone = String.duplicate("1", 25)
      attrs = %{email: "test@example.com", name: "Test User", phone: long_phone, role: :rider}
      changeset = User.changeset(%User{}, attrs)
      
      refute changeset.valid?
      assert "should be at most 20 character(s)" in errors_on(changeset).phone
    end

    test "validates role inclusion" do
      attrs = %{email: "test@example.com", name: "Test User", role: :invalid_role}
      changeset = User.changeset(%User{}, attrs)
      
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).role
    end

    test "accepts driver role" do
      attrs = %{email: "test@example.com", name: "Test User", role: :driver}
      changeset = User.changeset(%User{}, attrs)
      
      assert changeset.valid?
    end

    test "accepts rider role" do
      attrs = %{email: "test@example.com", name: "Test User", role: :rider}
      changeset = User.changeset(%User{}, attrs)
      
      assert changeset.valid?
    end
  end

  describe "registration_changeset/3" do
    test "valid registration changeset" do
      attrs = %{
        email: "test@example.com",
        name: "Test User",
        phone: "+1234567890",
        password: "Password123!",
        password_confirmation: "Password123!",
        role: :rider
      }

      changeset = User.registration_changeset(%User{}, attrs)
      assert changeset.valid?
      assert get_change(changeset, :password_hash)
      refute get_change(changeset, :password)
      refute get_change(changeset, :password_confirmation)
    end

    test "requires password" do
      attrs = %{
        email: "test@example.com",
        name: "Test User",
        role: :rider
      }

      changeset = User.registration_changeset(%User{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).password
    end

    test "validates password length - too short" do
      attrs = %{
        email: "test@example.com",
        name: "Test User",
        password: "Pass1!",
        password_confirmation: "Pass1!",
        role: :rider
      }

      changeset = User.registration_changeset(%User{}, attrs)
      refute changeset.valid?
      assert "should be at least 8 character(s)" in errors_on(changeset).password
    end

    test "validates password length - too long" do
      long_password = String.duplicate("a", 70) <> "A1!"
      attrs = %{
        email: "test@example.com",
        name: "Test User",
        password: long_password,
        password_confirmation: long_password,
        role: :rider
      }

      changeset = User.registration_changeset(%User{}, attrs)
      refute changeset.valid?
      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "validates password requires lowercase" do
      attrs = %{
        email: "test@example.com",
        name: "Test User",
        password: "PASSWORD123!",
        password_confirmation: "PASSWORD123!",
        role: :rider
      }

      changeset = User.registration_changeset(%User{}, attrs)
      refute changeset.valid?
      assert "at least one lower case character" in errors_on(changeset).password
    end

    test "validates password requires uppercase" do
      attrs = %{
        email: "test@example.com",
        name: "Test User",
        password: "password123!",
        password_confirmation: "password123!",
        role: :rider
      }

      changeset = User.registration_changeset(%User{}, attrs)
      refute changeset.valid?
      assert "at least one upper case character" in errors_on(changeset).password
    end

    test "validates password requires digit or punctuation" do
      attrs = %{
        email: "test@example.com",
        name: "Test User",
        password: "PasswordOnly",
        password_confirmation: "PasswordOnly",
        role: :rider
      }

      changeset = User.registration_changeset(%User{}, attrs)
      refute changeset.valid?
      assert "at least one digit or punctuation character" in errors_on(changeset).password
    end

    test "validates password confirmation" do
      attrs = %{
        email: "test@example.com",
        name: "Test User",
        password: "Password123!",
        password_confirmation: "DifferentPassword123!",
        role: :rider
      }

      changeset = User.registration_changeset(%User{}, attrs)
      refute changeset.valid?
      assert "does not match password" in errors_on(changeset).password_confirmation
    end

    test "does not hash password when hash_password: false" do
      attrs = %{
        email: "test@example.com",
        name: "Test User",
        password: "Password123!",
        password_confirmation: "Password123!",
        role: :rider
      }

      changeset = User.registration_changeset(%User{}, attrs, hash_password: false)
      assert changeset.valid?
      assert get_change(changeset, :password) == "Password123!"
      refute get_change(changeset, :password_hash)
    end

    test "validates password byte length when hashing" do
      # Create a password that's over 72 bytes but meets other requirements
      # Using multibyte characters to ensure we exceed byte limit
      base_password = "Password123!"
      # Add multibyte characters to exceed 72 bytes
      long_password = base_password <> String.duplicate("ñ", 35) # Base is 12 bytes + 35*2 = 82 bytes total
      attrs = %{
        email: "test@example.com",
        name: "Test User",
        password: long_password,
        password_confirmation: long_password,
        role: :rider
      }

      changeset = User.registration_changeset(%User{}, attrs)
      refute changeset.valid?
      assert "should be at most 72 byte(s)" in errors_on(changeset).password
    end
  end
end