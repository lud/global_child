defmodule GlobalChild.Test.GS do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, [], name: opts[:name])
  end

  def get_node(server) do
    GenServer.call(server, :get_node)
  end

  def init(_) do
    {:ok, nil}
  end

  def handle_call(:get_node, _, state) do
    {:reply, node(), state}
  end
end
