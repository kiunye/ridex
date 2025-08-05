defmodule Ridex.Repo do
  use Ecto.Repo,
    otp_app: :ridex,
    adapter: Ecto.Adapters.Postgres

  def init(_, opts) do
    {:ok, Keyword.put(opts, :url, System.get_env("DATABASE_URL") || build_url(opts))}
  end

  defp build_url(opts) do
    "ecto://#{opts[:username]}:#{opts[:password]}@#{opts[:hostname]}/#{opts[:database]}"
  end
end
