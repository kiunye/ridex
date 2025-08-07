defmodule RidexWeb.PageController do
  use RidexWeb, :controller

  def home(conn, _params) do
    # Just render the home page - let users navigate to their dashboards via links
    render(conn, :home)
  end
end
