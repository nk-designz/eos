defmodule EosWeb.PageController do
  use EosWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
