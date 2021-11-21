defmodule GlobalChild.Test.Server do
  use GenServer
  require Logger

  @moduledoc """
  false
  """

  def child_spec(opts) do
    case Keyword.pop(opts, :id) do
      {nil, opts} -> super(opts)
      {id, opts} -> opts |> super() |> Supervisor.child_spec(id: id)
    end
  end

  def start_link(opts) do
    # Logger.debug(
    #   "#{inspect(node())} starting #{inspect(__MODULE__)} with name: #{inspect(opts[:name])}"
    # )

    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  def get_info(server) do
    GenServer.call(server, :get_info)
  end

  def init(opts) do
    # Logger.debug("#{inspect(node())} #{inspect(__MODULE__)} init")
    Process.flag(:trap_exit, true)

    case opts[:pingback] do
      pid when is_pid(pid) -> send(pid, {:hello_from, self(), node()})
      nil -> :ok
    end

    {:ok, nil}
  end

  def handle_call(:get_info, _, state) do
    {:reply, {self(), node()}, state}
  end

  def handle_info(_info, _, state) do
    # Logger.debug("#{inspect(node())} #{inspect(__MODULE__)} info: #{inspect(info)}")
    {:noreply, state}
  end

  def terminate(_reason, _state) do
    # Logger.debug("#{inspect(node())} #{inspect(__MODULE__)} terminating: #{inspect(reason)}")
  end
end
