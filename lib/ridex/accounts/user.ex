defmodule Ridex.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :email, :string
    field :name, :string
    field :phone, :string
    field :password_hash, :string
    field :role, Ecto.Enum, values: [:driver, :rider]

    # Virtual field for password input
    field :password, :string, virtual: true
    field :password_confirmation, :string, virtual: true

    has_one :driver, Ridex.Drivers.Driver
    has_one :rider, Ridex.Riders.Rider

    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :phone, :role])
    |> validate_required([:email, :name, :role])
    |> validate_email()
    |> validate_phone()
    |> validate_role()
    |> unique_constraint(:email)
  end

  @doc """
  A user changeset for registration.

  It is important to validate the length of both email and password.
  Otherwise databases may truncate the email without warnings, which
  could lead to unpredictable or insecure behaviour. Long passwords may
  also be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :name, :phone, :password, :password_confirmation, :role])
    |> validate_required([:email, :name, :password, :role])
    |> validate_email()
    |> validate_phone()
    |> validate_password(opts)
    |> validate_role()
  end

  defp validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> unique_constraint(:email)
  end

  defp validate_phone(changeset) do
    changeset
    |> validate_format(:phone, ~r/^\+?[1-9]\d{1,14}$/,
        message: "must be a valid phone number")
    |> validate_length(:phone, min: 10, max: 20)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 8, max: 72)
    |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> validate_confirmation(:password, message: "does not match password")
    |> maybe_hash_password(opts)
  end

  defp validate_role(changeset) do
    changeset
    |> validate_required([:role])
    |> validate_inclusion(:role, [:driver, :rider])
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)
      # Hashes the password and stores it in the password_hash field
      |> put_change(:password_hash, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
      |> delete_change(:password_confirmation)
    else
      changeset
    end
  end
end
