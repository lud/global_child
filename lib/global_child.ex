defmodule GlobalChild do
  require Logger
  use Supervisor
  require Logger

  @moduledoc """

  ### Options

  * `child` – Required. The child specification for the global process to start.
  * `startup_sleep` – Optional, defaults to `0`. A duration in milliseconds to
    sleep for before attempting to start the global child.  This is useful to
    let the cluster form up as it allows `:global` to synchronize with other
    nodes.
  * `monitor_sleep` - Optional, defaults to `0`. A duration in milliseconds to
    sleep for before monitoring the global child started on another node.  This
    allows the global child supervisor to finish its initialization (for
    instance `c:GenServer.init/1`) before attempting to monitor it.
  """

  def child_spec(opts) do
    # The child spec of the child dedicated supervisor is derived from the child
    # spec of the child.  We use the same id and restart.

    child_child_spec = opts |> Keyword.fetch!(:child) |> Supervisor.child_spec([])

    child_id = child_child_spec.id
    child_restart = Map.get(child_child_spec, :restart, :permanent)

    %{
      id: child_id,
      start: {Supervisor, :start_link, [__MODULE__, {child_child_spec, opts}, []]},
      restart: child_restart,
      type: :supervisor
    }
  end

  defp log(child_id, message) do
    Logger.debug("[#{inspect(__MODULE__)}::#{inspect(child_id)}] #{message}")
  end

  @impl true
  def init({child_child_spec, opts}) do
    # When initializing the supervisor we try to acquire the global lock for
    # that child.  If the lock is acquired we actually start the child.
    # Otherwise we start a taks that will monitor the process registered on
    # another node.
    child_id = child_child_spec.id

    children =
      if acquire_lock?(child_id) do
        [child_child_spec]
      else
        [{GlobalChild.Monitor, child_id: child_id}]
      end

    # max_restarts is set to zero because the supervisor is a surrogate for the
    # actual child. If the child dies (be it the monitor or the actual child),
    # so does the supervisor. If we were supervising the monitor, on restart we
    # may now acquire the lock and supervise the actual child.
    Supervisor.init(children, strategy: :one_for_all, max_restarts: 0)
  end

  def lock_name(child_id) do
    {__MODULE__.Lock, child_id}
  end

  def maybe_sleep(n) when is_integer(n) and n > 0, do: Process.sleep(n)
  def maybe_sleep(0), do: :ok
  def maybe_sleep(nil), do: :ok

  defp acquire_lock?(child_id) do
    # We do not use the lock mechanism of :global but a name registration.  This
    # allows to find the lock owner by name when monitoring other nodes without
    # needing to know the registration name of the global child.

    case :global.register_name(lock_name(child_id), self(), &handle_lock_conflict/3) do
      :yes ->
        log(child_id, "acquired lock")
        true

      :no ->
        log(child_id, "lock already taken")
        false
    end
  end

  defp handle_lock_conflict({__MODULE__.Lock, child_id}, pid1, pid2) do
    log(child_id, "lock conflict, stopping child")

    try do
      Supervisor.stop(pid1)
    catch
      :exit, {:noproc, {GenServer, :stop, _}} -> :ok
      :exit, {{{:nodedown, _}, _}, {GenServer, :stop, _}} -> :ok
    end

    pid2
  end
end

defmodule GlobalChild.Monitor do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    child_id = Keyword.fetch!(opts, :child_id)
    lock_name = GlobalChild.lock_name(child_id)

    opts |> IO.inspect(label: "opts")
    Logger.debug("looking for monitor for #{inspect(child_id)}")

    case monitor_lock_owner(lock_name, opts) do
      {:ok, ref} -> {:ok, {child_id, ref}}
      :error -> {:stop, {:shutdown, :global_child_lock_not_found}}
    end
  end

  defp monitor_lock_owner(lock_name, opts) do
    # this function retrieves the lock owner supervisor, and not the actual
    # global child.
    case :global.whereis_name(lock_name) do
      :undefined ->
        :error

      pid ->
        # If we manage to get the pid of the supervisor, we want to block until
        # the global child has finished initialization, be cause other processes
        # in the parent supervision tree (where GlobalChild is inserted) may
        # expect that previous child is started and registered. So we will call
        # the supervisor with a dummy call.
        ref = Process.monitor(pid)
        [_] = Supervisor.which_children(pid)
        {:ok, ref}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, {child_id, ref} = state) do
    Logger.warn("global child #{inspect(child_id)} died: #{inspect(reason)}")
    {:stop, {:shutdown, {:gobal_child_supervisor_exit, reason}}, state}
  end
end
