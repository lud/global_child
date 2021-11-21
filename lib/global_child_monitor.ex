defmodule GlobalChild.Monitor do
  use GenServer
  require Logger

  @moduledoc false

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    case monitor_lock_owner(opts) do
      {:ok, ref} -> {:ok, Map.put(opts, :ref, ref)}
      :error -> {:stop, {:shutdown, :global_child_lock_not_found}}
    end
  end

  defp monitor_lock_owner(%{child_id: child_id} = opts) do
    lock_name = GlobalChild.lock_name(child_id)

    # this call retrieves the lock owner supervisor, and not the actual
    # global child.
    case :global.whereis_name(lock_name) do
      :undefined ->
        GlobalChild.maybe_log(opts, :warn, child_id, "could not find remote global child")
        :error

      pid ->
        # If we manage to get the pid of the supervisor, we want to block until
        # the global child has finished initialization, be cause other processes
        # in the parent supervision tree (where GlobalChild is inserted) may
        # expect that previous child is started and registered. So we will call
        # the supervisor with a dummy call.
        ref = Process.monitor(pid)
        [_] = Supervisor.which_children(pid)
        GlobalChild.maybe_log(opts, :debug, child_id, "monitoring remote global child")
        {:ok, ref}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{child_id: child_id, ref: ref} = state) do
    GlobalChild.maybe_log(state, :warn, child_id, "global child is down: #{inspect(reason)}")
    {:stop, reason, state}
  end
end
