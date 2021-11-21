defmodule GlobalChild.Test.Server do
  use GenServer

  def child_spec(opts) do
    case Keyword.pop(opts, :id) do
      {nil, opts} -> super(opts)
      {id, opts} -> opts |> super() |> Supervisor.child_spec(id: id)
    end
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  def get_info(server) do
    GenServer.call(server, :get_info)
  end

  def init(opts) do
    case opts[:pingback] do
      pid when is_pid(pid) -> send(pid, {:hello_from, self(), node()})
      nil -> :ok
    end

    {:ok, nil}
  end

  def handle_call(:get_info, _, state) do
    {:reply, {self(), node()}, state}
  end
end
