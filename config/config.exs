import Config

config :logger, :console, format: "$metadata[$level] $message\n", metadata: [:pid]

config :global_child,
  debug: false,
  sleep: 0
