defmodule GlobalChild.Test.Server do
  use GenServer
  require Logger

  @moduledoc """
  false
  """

  def child_spec(opts) do
    cs = super(opts)

    cs =
      case Keyword.get(opts, :id) do
        nil -> cs
        id -> Supervisor.child_spec(cs, id: id)
      end

    cs =
      case Keyword.get(opts, :restart) do
        nil -> cs
        restart -> Supervisor.child_spec(cs, restart: restart)
      end

    cs
  end

  def start_link(opts) do
    # Logger.debug(
    #   "#{inspect(node())} starting #{inspect(__MODULE__)} with name: #{inspect(opts[:name])}"
    # )

    IO.puts("starting #{inspect(__MODULE__)} as #{inspect(opts[:name])}")
    GenServer.start_link(__MODULE__, opts)
  end

  def get_info(server) do
    GenServer.call(server, :get_info)
  end

  def init(opts) do
    # Logger.debug("#{inspect(node())} #{inspect(__MODULE__)} init")
    Process.flag(:trap_exit, true)

    case opts[:name] do
      {:global, name} -> :yes = :global.register_name(name, self(), &handle_name_conflict/3)
      name when is_atom(name) -> Process.register(name, self())
      nil -> :ok
    end

    case opts[:pingback] do
      pid when is_pid(pid) -> send(pid, {:hello_from, self(), node()})
      nil -> :ok
    end

    {:ok, nil}
  end

  def handle_name_conflict(_name, pid1, pid2) do
    Process.exit(pid1, :name_conflict_in_test_server)
    pid2
  end

  def handle_call(:get_info, _, state) do
    {:reply, {self(), node()}, state}
  end

  def handle_info({:EXIT, _, reason}, state) do
    # Logger.debug("#{inspect(node())} #{inspect(__MODULE__)} info: #{inspect(info)}")
    {:stop, reason, state}
  end

  def handle_info(_info, state) do
    # Logger.debug("#{inspect(node())} #{inspect(__MODULE__)} info: #{inspect(info)}")
    {:noreply, state}
  end

  def terminate(_reason, _state) do
    # Logger.debug("#{inspect(node())} #{inspect(__MODULE__)} terminating: #{inspect(reason)}")
  end
end
