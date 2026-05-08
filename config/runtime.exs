import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/eos start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :eos, EosWeb.Endpoint, server: true
end

config :eos, EosWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :eos, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :eos, EosWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
    secret_key_base: secret_key_base
end

# EOS IoT Agent configuration
config :eos,
  phaeton_url: System.get_env("PHAETON_URL", "http://localhost:4001"),
  phaeton_agent_token: System.get_env("PHAETON_AGENT_TOKEN", ""),
  agent_base_url: System.get_env("AGENT_BASE_URL", "http://localhost:4000"),
  agent_ws_url: System.get_env("AGENT_WS_URL", "ws://localhost:4000/plugins"),
  plugin_token_secret:
    System.get_env("PLUGIN_TOKEN_SECRET") || raise("PLUGIN_TOKEN_SECRET is required"),
  k8s_namespace: System.get_env("K8S_NAMESPACE", "default"),
  k8s_conn: System.get_env("KUBECONFIG"),
  tenants: System.get_env("TENANTS", "default") |> String.split(",") |> Enum.map(&String.trim/1)
