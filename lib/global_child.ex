defmodule GlobalChild do
  use Supervisor
  require Logger

  def child_spec(opts) do
    child_child_spec = opts |> Keyword.fetch!(:child) |> Supervisor.child_spec([])
    {:global, name} = Keyword.fetch!(opts, :name)

    %{
      id: child_child_spec.id,
      start:
        {Supervisor, :start_link, [__MODULE__, {child_child_spec, {:global, name}, opts}, []]},
      type: :supervisor
    }
  end

  @impl true
  def init({child_child_spec, {:global, name}, opts}) do
    maybe_sleep(opts[:sleep])

    # The task will use the restart configuration of the child we want to
    # manage, and the child will be set to temporary. If the child was transient
    # or permanent, so will be the Task, and the Task always tries to start the
    # child, so the child is "logically" transient or permanent, but at a
    # cluster level.
    task_restart = Map.get(child_child_spec, :restart, :permanent)
    child_child_spec = Map.put(child_child_spec, :restart, :temporary)

    parent = self()

    children = [
      Supervisor.child_spec(
        {Task, fn -> manage_child(child_child_spec, {:global, name}, parent, opts) end},
        restart: task_restart
      )
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp maybe_sleep(n) when is_integer(n) and n > 0, do: Process.sleep(n)
  defp maybe_sleep(0), do: :ok
  defp maybe_sleep(nil), do: :ok

  defp manage_child(child_child_spec, {:global, name}, parent, opts) do
    IO.puts("-------------------------------------------------------------------")

    state = %{
      spec: child_child_spec,
      name: {:global, name},
      parent: parent,
      opts: opts,
      # we should use a lock scoped to the child, not global for the library
      lock: __MODULE__
    }

    Logger.warn("global child manager starting")
    monitor(state)
  end

  defp monitor(state) do
    case check_registered(state.name) do
      {true, pid} ->
        await_down(pid)

      false ->
        Logger.warn("#{inspect(state.name)} is not registered, starting the child")
        start_register(state)
    end
  end

  defp check_registered({:global, name}) do
    :global.whereis_name(name) |> cast_whereis()
  end

  defp cast_whereis(pid) when is_pid(pid), do: {true, pid}
  defp cast_whereis(:undefined), do: false
  defp cast_whereis(nil), do: false

  defp await_down(pid) do
    ref = Process.monitor(pid)
    Logger.warn("global child manager monitoring #{inspect(pid)}")

    # Once the existing server is down we will restart and try to register our
    # child again.
    receive do
      {:DOWN, ^ref, :process, ^pid, reason} -> exit({:shutdown, reason})
    end
  end

  def start_register(state) do
    start = fn ->
      state.spec |> IO.inspect(label: ~S[state.spec])
      Supervisor.start_child(state.parent, state.spec)
    end

    case under_lock(state, start) do
      {:ok, pid} ->
        register(pid, state)

      {:error, :locked} ->
        maybe_sleep(state.opts[:delay])
        monitor(state)
    end
  end

  def under_lock(state, f) do
    state.lock |> IO.inspect(label: ~S[state.lock])
    locked? = :global.set_lock({state.lock, make_ref()}, [node() | Node.list()], 0)
    locked? |> IO.inspect(label: ~S[locked?])

    case locked? do
      true ->
        result = f.()
        # :global.del_lock(state.lock)
        result

      false ->
        {:error, :locked}
    end
  end

  def register(pid, %{name: {:global, name}} = state) do
    case :global.register_name(name, pid, &__MODULE__.resolve_global/3) do
      # When the child will exit, we will restart because the supervisor is
      # :one_for_all. But to cover a :normal exit reason we have to monitor the
      # child.
      :yes -> await_down(pid)
      # If the name could not be registered, we will exit and retry
      :no -> exit(:normal)
    end
  end

  def resolve_global(name, pid1, pid2) do
    binding() |> IO.inspect(label: ~S[binding()])
    Process.exit(pid2, {:global_name_conflict, name})
    pid1
  end
end
