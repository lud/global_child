# GlobalChild

**TODO: Add description**

## Installation

```elixir
def deps do
  [
    {:global_child, "~> 0.1.1"},
  ]
end
```

## [Documentation](https://hexdocs.pm/global_child)

The documentation is available on [hexdocs.pm](https://hexdocs.pm/global_child)

<!-- moduledoc_start -->

## Usage

To start a globally unique child, wrap its child spec with a `GlobalChild`
child spec tuple:

```elixir
children = [
  # ...
  {GlobalChild, child: {MyApp.Worker, name: {:global, :worker}}},
  # ...
]
```

**Options**

* `:child` – Required. The child specification of the global process.
* `:debug` – Optional, defaults to `false`. Enables logger debug message when
  `true`.
* `:sleep` – Optional, defaults to `0`. A duration in milliseconds to sleep
  for before attempting to start the global child.  This is useful to let the
  cluster form and allow `:global` to synchronize with other nodes.  Without a
  delay, the process may start on several nodes, though eventually there will
  only be one left after `:global` is synchronized.  See `:global.sync/0` if
  you need to enforce the synchronization.


## Configuration

The default values for `:debug` and `:sleep` options can be set at the
configuration level.  Those values are pulled at runtime.

```elixir
config :global_child,
debug: true,
sleep: 1500
```