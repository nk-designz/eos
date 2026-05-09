defmodule EosWeb.HealthController do
  use EosWeb, :controller

  def check(conn, _params) do
    send_resp(conn, 200, "ok")
  end
end
