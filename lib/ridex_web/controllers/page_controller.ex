defmodule RidexWeb.PageController do
  use RidexWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
