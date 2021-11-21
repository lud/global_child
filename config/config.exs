import Config

config :logger, :console, format: "$metadata[$level] $message\n"
config :global_child, debug: true, sleep: 0
