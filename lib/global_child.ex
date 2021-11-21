defmodule GlobalChild do
  require Logger
  use Supervisor
  require Logger

  @readme __ENV__.file
          |> Path.dirname()
          |> Path.dirname()
          |> Path.join("README.md")
          |> File.read!()
          |> String.split("<!-- moduledoc_start -->", parts: 2, trim: true)
          |> Enum.at(1)

  @moduledoc """
  Simple utility to provide a globally unique process in a cluster of Elixir
  nodes.

  #{@readme}
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

  @doc false
  def log(level, child_id, message) do
    Logger.log(
      level,
      "[#{inspect(__MODULE__)} #{inspect(node())} #{inspect(child_id)}] #{message}"
    )
  end

  @doc false
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

  @doc false
  def lock_name(child_id) do
    {__MODULE__.Lock, child_id}
  end

  defp build_opts(opts) do
    Map.merge(default_opts(), Map.new(opts))
  end

  defp default_opts do
    env = Application.get_all_env(:global_child)

    %{
      sleep: Keyword.get(env, :sleep, 0),
      debug: Keyword.get(env, :debug, false)
    }
  end

  defp maybe_sleep(n) when is_integer(n) and n > 0, do: Process.sleep(n)
  defp maybe_sleep(0), do: :ok
  defp maybe_sleep(nil), do: :ok

  defp acquire_lock?(child_id, opts) do
    # We do not use the lock mechanism of :global but a name registration.  This
    # allows to find the lock owner by name when monitoring other nodes without
    # needing to know the registration name of the global child.
    lock = lock_name(child_id)
    maybe_log(opts, child_id, "acquiring lock #{inspect(lock)}")

    case :global.register_name(lock, self(), &handle_lock_conflict/3) do
      :yes ->
        maybe_log(opts, child_id, "acquired lock")
        true

      :no ->
        maybe_log(opts, child_id, "remote child exists")
        false
    end
  end

  defp handle_lock_conflict({__MODULE__.Lock, _} = lock, pid1, pid2) do
    try do
      Process.exit(pid1, :name_conflict)
      # :ok = Supervisor.stop(pid1, :name_conflict)
    catch
      :exit, {:noproc, {GenServer, :stop, _}} ->
        :ok

      :exit, {{{:nodedown, _}, _}, {GenServer, :stop, _}} ->
        :ok

      kind, reason ->
        "#{inspect(kind)} in GlobalChild.handle_lock_conflict(#{inspect(lock)}, #{inspect(pid1)}, #{inspect(pid2)}): #{inspect(reason)}"
        |> Logger.error()
    end

    pid2
  end
end
