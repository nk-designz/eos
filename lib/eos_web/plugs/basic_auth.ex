defmodule EosWeb.Plugs.BasicAuth do
  @moduledoc false

  import Plug.BasicAuth

  def init(opts), do: opts

  def call(conn, _opts) do
    username = Application.get_env(:eos, :basic_auth_username, "admin")
    password = Application.get_env(:eos, :basic_auth_password, "start-123")
    basic_auth(conn, username: username, password: password)
  end
end
