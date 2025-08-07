defmodule Ridex.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Ridex.Repo

  alias Ridex.Accounts.User

  @doc """
  Returns the list of users.

  ## Examples

      iex> list_users()
      [%User{}, ...]

  """
  def list_users do
    Repo.all(User)
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Gets a single user by id.

  ## Examples

      iex> get_user(123)
      %User{}

      iex> get_user(456)
      nil

  """
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("user@example.com")
      %User{}

      iex> get_user_by_email("nonexistent@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Creates a user.

  ## Examples

      iex> create_user(%{field: value})
      {:ok, %User{}}

      iex> create_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a user and their associated profile (driver or rider).

  ## Examples

      iex> create_user_with_profile(%{role: "driver", email: "driver@example.com"})
      {:ok, %User{}}

      iex> create_user_with_profile(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_user_with_profile(attrs \\ %{}) do
    Repo.transaction(fn ->
      with {:ok, user} <- create_user(attrs),
           {:ok, _profile} <- create_user_profile(user, attrs) do
        user
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp create_user_profile(%User{role: :driver} = user, _attrs) do
    Ridex.Drivers.create_driver(%{user_id: user.id})
  end

  defp create_user_profile(%User{role: :rider} = user, _attrs) do
    Ridex.Riders.create_rider(%{user_id: user.id})
  end

  defp create_user_profile(_user, _attrs) do
    {:ok, nil}  # No profile needed for other roles
  end

  @doc """
  Updates a user.

  ## Examples

      iex> update_user(user, %{field: new_value})
      {:ok, %User{}}

      iex> update_user(user, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user.

  ## Examples

      iex> delete_user(user)
      {:ok, %User{}}

      iex> delete_user(user)
      {:error, %Ecto.Changeset{}}

  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end

  @doc """
  Authenticates a user with email and password.

  ## Examples

      iex> authenticate_user("user@example.com", "correct_password")
      {:ok, %User{}}

      iex> authenticate_user("user@example.com", "wrong_password")
      {:error, :invalid_credentials}

      iex> authenticate_user("nonexistent@example.com", "password")
      {:error, :invalid_credentials}

  """
  def authenticate_user(email, password) when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)

    cond do
      user && Bcrypt.verify_pass(password, user.password_hash) ->
        {:ok, user}

      user ->
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}

      true ->
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  @doc """
  Returns a registration changeset for tracking user changes during registration.

  ## Examples

      iex> change_user_registration()
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(attrs \\ %{}) do
    User.registration_changeset(%User{}, attrs)
  end

  alias Ridex.Accounts.UserToken

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  @doc """
  Generates a socket token for a user.
  """
  def generate_user_socket_token(user) do
    Phoenix.Token.sign(RidexWeb.Endpoint, "user socket", user.id)
  end
end
