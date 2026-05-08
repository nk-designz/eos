defmodule Eos.Plugins.Token do
  @moduledoc """
  Generates and verifies per-plugin authentication tokens.

  Tokens are signed HMAC-SHA256 over the plugin_id using a secret from
  the `PLUGIN_TOKEN_SECRET` environment variable. The token format is:
  `<plugin_id>.<base64url(hmac)>`
  """

  @hash :sha256

  defp secret do
    Application.fetch_env!(:eos, :plugin_token_secret)
  end

  def generate(plugin_id) do
    mac = :crypto.mac(:hmac, @hash, secret(), plugin_id)
    encoded = Base.url_encode64(mac, padding: false)
    "#{plugin_id}.#{encoded}"
  end

  def verify(token) do
    case String.split(token, ".", parts: 2) do
      [plugin_id, provided_mac] ->
        expected_mac = :crypto.mac(:hmac, @hash, secret(), plugin_id)
        expected_encoded = Base.url_encode64(expected_mac, padding: false)

        if Plug.Crypto.secure_compare(provided_mac, expected_encoded) do
          {:ok, plugin_id}
        else
          {:error, :invalid_token}
        end

      _ ->
        {:error, :malformed_token}
    end
  end
end
