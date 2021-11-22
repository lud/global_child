defmodule GlobalChild do
  require Logger
  use GenServer
  require Logger
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

  defmodule S do
    @moduledoc false
    @enforce_keys [:debug, :child_id, :child_spec, :current, :restart]
    defstruct @enforce_keys
  end

  require Record
  Record.defrecordp(:__actual, :actual, sup_pid: nil, child_pid: nil)
  Record.defrecordp(:__monitor, :monitor, ref: nil)

  def child_spec(opts) when is_tuple(opts) when is_atom(opts) when is_map(opts) do
    child_spec(child: opts)
  end

  def child_spec(opts) do
    # The child spec of the child dedicated supervisor is derived from the child
    # spec of the child.  We use the same id and restart.

    {child_child_spec, opts} = Keyword.pop!(opts, :child)
    child_child_spec = Supervisor.child_spec(child_child_spec, [])

    child_id = child_child_spec.id
    child_restart = Map.get(child_child_spec, :restart, :permanent)

    # finally we override the child so it is temporary.  That is because we want
    # the global child parent (this module) exit with the same reason when the
    # global child exits, so we do not want it to be restarted by its
    # supervisor.
    child_child_spec = Map.put(child_child_spec, :restart, :temporary)

    opts =
      build_opts(opts, child_id: child_id, child_spec: child_child_spec, restart: child_restart)

    %{
      id: child_id,
      start: {GenServer, :start_link, [__MODULE__, opts, []]},
      restart: child_restart,
      # we declare a type of supervisor so we will let our inner supervisor
      # handle shutdown time properly.
      type: :supervisor
    }
  end

  defp default_opts do
    env = Application.get_all_env(:global_child)

    %{
      sleep: Keyword.get(env, :sleep, 0),
      debug: Keyword.get(env, :debug, false)
    }
  end

  def status(server) do
    GenServer.call(server, :get_status)
  end

  @impl true
  def init(state) do
    maybe_sleep(state.sleep)
    {_, state} = Map.pop!(state, :sleep)
    maybe_log(state, "initializing")
    Process.flag(:trap_exit, true)
    {:ok, register(struct!(S, Map.put(state, :current, nil)))}
  end

  @impl true
  def handle_info(
        {:DOWN, ref, :process, _, reason},
        %S{current: __monitor(ref: ref), restart: restart} = state
      ) do
    state = Map.put(state, :current, nil)

    case {restart, reason} do
      # Child must not be taken over if it is transient with a normal-ish
      # reason, or if it is temporary.
      {:transient, :normal} -> {:stop, reason, state}
      {:transient, :shutdown} -> {:stop, reason, state}
      {:transient, {:shutdown, _}} -> {:stop, reason, state}
      {:temporary, _} -> {:stop, reason, state}
      # Otherwise we try to take over
      # _ -> {:noreply, register(state)}
      _ -> {:stop, {:shutdown, reason}, state}
    end
  end

  def handle_info(
        {:EXIT, _pid, :"$global_child_resolve_conflict"},
        %S{current: __actual(sup_pid: sup_pid), restart: restart} = state
      ) do
    maybe_log(state, :warn, "name conflict")
    :ok = Supervisor.stop(sup_pid, :shutdown)
    maybe_log(state, :warn, "stopped local global child")

    reason =
      case restart do
        # We are going to stop for a name conflict. If we are transient, we want to
        # be restarted to become a monitor.  So we stop with a non-normal reason.
        :transient -> :name_conflict
        _ -> {:shutdown, :name_conflict}
      end

    {:stop, reason, Map.put(state, :current, nil)}
  end

  def handle_info({:EXIT, sup_pid, _}, %S{current: __actual(sup_pid: sup_pid)} = state) do
    # The supervisor exited. This is unexpected.
    {:stop, :global_child_supervisor_exit, Map.put(state, :current, nil)}
  end

  def handle_info({:EXIT, child_pid, reason}, %S{current: __actual(child_pid: child_pid)} = state) do
    # The local global child has died.  We stop with the same reason to let our
    # parent supervisor handle the restart according to reason.

    maybe_log(
      state,
      :warn,
      "local global child exited with reason: #{inspect(reason)}, stopping with same reason"
    )

    {:stop, reason, Map.put(state, :current, nil)}
  end

  @impl true

  def handle_call(:get_status, _from, %S{current: __actual(child_pid: child_pid)} = state) do
    {:reply, {:actual, child_pid}, state}
  end

  def handle_call(:get_status, _from, %S{current: __monitor()} = state) do
    {:reply, :monitor, state}
  end

  @impl true
  def terminate(reason, %S{current: __actual(sup_pid: sup_pid)} = state) do
    maybe_log(state, :debug, "terminating with reason: #{inspect(reason)}")
    :ok = Supervisor.stop(sup_pid, reason)
    maybe_log(state, :warn, "stopped local global child")
  end

  def terminate(reason, %S{} = state) do
    maybe_log(state, :debug, "terminating with reason: #{inspect(reason)}")
    :ok
  end

  defp lock_name(%{child_id: id}) do
    {__MODULE__, id}
  end

  defp handle_conflict(_name, pid1, pid2) do
    Process.exit(pid2, :"$global_child_resolve_conflict")
    pid1
  end

  defp register(%S{current: nil} = state) do
    case :global.register_name(lock_name(state), self(), &handle_conflict/3) do
      :yes ->
        maybe_log(state, :debug, "acquired lock")
        start(state)

      :no ->
        monitor(state)
    end
  end

  defp start(%S{current: nil, child_id: id} = state) do
    maybe_log(state, :debug, "starting global child")

    {:ok, sup_pid} = Supervisor.start_link([state.child_spec], strategy: :one_for_one)

    [{^id, child_pid, _, _}] = Supervisor.which_children(sup_pid)

    # We link to the child so we can monitor its death
    Process.link(child_pid)
    Map.put(state, :current, __actual(sup_pid: sup_pid, child_pid: child_pid))
  end

  defp monitor(%S{current: nil} = state) do
    case :global.whereis_name(lock_name(state)) do
      :undefined ->
        maybe_log(state, :warn, "remote global child not found")
        register(state)

      pid ->
        maybe_log(state, :debug, "monitoring remote global child #{inspect(pid)}")
        ref = Process.monitor(pid)
        Map.put(state, :current, __monitor(ref: ref))
    end
  end

  @doc false
  def log(level, child_id, message) do
    Logger.log(
      level,
      "[#{inspect(__MODULE__)} #{inspect(node())} #{inspect(child_id)}] #{message}"
    )
  end

  @doc false
  def maybe_log(opts, level \\ :debug, message)

  def maybe_log(%{debug: true, child_id: child_id}, level, message) do
    log(level, child_id, message)
  end

  def maybe_log(%{debug: false}, _, _) do
    :ok
  end

  defp build_opts(opts, more_opts) do
    default_opts()
    |> Map.merge(Map.new(opts))
    |> Map.merge(Map.new(more_opts))
  end

  defp maybe_sleep(n) when is_integer(n) and n > 0, do: Process.sleep(n)
  defp maybe_sleep(0), do: :ok
  defp maybe_sleep(nil), do: :ok
end
