ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Ridex.Repo, :manual)

# Load fixtures
Code.require_file("support/fixtures/accounts_fixtures.ex", __DIR__)
