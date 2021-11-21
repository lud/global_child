defmodule GlobalChild do
  require Logger
  use Supervisor
  require Logger

  @moduledoc """

  ### Options

  * `child` – Required. The child specification for the global process to start.
  * `sleep` – Optional, defaults to `0`. A duration in milliseconds to sleep for
    before attempting to start the global child.  This is useful to let the
    cluster form up as it allows `:global` to synchronize with other nodes.
  * `debug` – Optional, defaults to `false`. Enables logger debug message when
    `true`.
  """

  def child_spec(opts) do
    # The child spec of the child dedicated supervisor is derived from the child
    # spec of the child.  We use the same id and restart.

    {child_child_spec, opts} = Keyword.pop!(opts, :child)
    child_child_spec = Supervisor.child_spec(child_child_spec, [])

    child_id = child_child_spec.id
    child_restart = Map.get(child_child_spec, :restart, :permanent)
    opts = build_opts(opts)

    %{
      id: child_id,
      start: {Supervisor, :start_link, [__MODULE__, {child_child_spec, opts}, []]},
      restart: child_restart,
      type: :supervisor
    }
  end

  defp log(level, child_id, message) do
    Logger.log(
      level,
      "[#{inspect(__MODULE__)} #{inspect(node())} #{inspect(child_id)}] #{message}"
    )
  end

  def maybe_log(opts, level \\ :debug, child_id, message)

  def maybe_log(%{debug: true}, level, child_id, message) do
    log(level, child_id, message)
  end

  def maybe_log(_, _, _, _) do
    :ok
  end

  @impl true
  def init({child_child_spec, opts}) do
    maybe_sleep(opts[:sleep])
    # When initializing the supervisor we try to acquire the global lock for
    # that child.  If the lock is acquired we actually start the child.
    # Otherwise we start a taks that will monitor the process registered on
    # another node.
    child_id = child_child_spec.id

    children =
      if acquire_lock?(child_id, opts) do
        [child_child_spec]
      else
        [{GlobalChild.Monitor, Map.put(opts, :child_id, child_id)}]
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

  defp build_opts(opts) do
    Map.merge(default_opts(), Map.new(opts))
  end

  defp default_opts do
    %{sleep: 0, debug: false}
  end

  def maybe_sleep(n) when is_integer(n) and n > 0, do: Process.sleep(n)
  def maybe_sleep(0), do: :ok
  def maybe_sleep(nil), do: :ok

  defp acquire_lock?(child_id, opts) do
    # We do not use the lock mechanism of :global but a name registration.  This
    # allows to find the lock owner by name when monitoring other nodes without
    # needing to know the registration name of the global child.

    case :global.register_name(lock_name(child_id), self(), &handle_lock_conflict/3) do
      :yes ->
        maybe_log(opts, child_id, "acquired lock")
        true

      :no ->
        maybe_log(opts, child_id, "lock already taken")
        false
    end
  end

  defp handle_lock_conflict({__MODULE__.Lock, _child_id}, pid1, pid2) do
    try do
      Supervisor.stop(pid1)
    catch
      :exit, {:noproc, {GenServer, :stop, _}} -> :ok
      :exit, {{{:nodedown, _}, _}, {GenServer, :stop, _}} -> :ok
    end

    pid2
  end
end
