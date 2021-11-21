defmodule GlobalChild.TestTools do
  require ExUnit.Assertions
  alias GlobalChild.Test.Server

  @moduledoc false

  def start_supervised_on_nodes(nodes, gc_spec) do
    for n <- nodes do
      {:ok, sup} = rpc(n, Supervisor, :start_link, [[gc_spec], [strategy: :one_for_one]])
      sup
    end
  end

  def rpc(node, m, f, a) do
    # IO.puts(
    #   "call on node #{inspect(node)} #{inspect(m)}.#{f}(#{Enum.map(a, &(&1 |> inspect)) |> Enum.join(", ")})"
    # )

    :rpc.block_call(node, m, f, a)
  end

  def rpc_all(nodes, m, f, a) do
    Enum.map(nodes, &rpc(&1, m, f, a))
  end

  def get_node_from(node, name) do
    case rpc(node, Server, :get_info, [name]) do
      {_, n} -> n
    end
  end

  def get_pid_from(node, name) do
    case rpc(node, Server, :get_info, [name]) do
      {pid, _} -> pid
    end
  end

  def heal_sync(nodes) do
    Schism.heal(nodes)
    ExUnit.Assertions.assert(Enum.all?(rpc_all(nodes, :global, :sync, []), &(&1 == :ok)))
    sync_nodes(nodes)
  end

  def sync_nodes(nodes) do
    ExUnit.Assertions.assert(Enum.all?(rpc_all(nodes, :global, :sync, []), &(&1 == :ok)))
  end

  # finds which kind of child were started under a global child supervisor,
  # itself started under a supervisor.
  def child_child_kind(gc_parent_parent) do
    case Supervisor.which_children(gc_parent_parent) do
      [{_id, pid, :supervisor, [GenServer]}] ->
        child_kind(pid)
    end
  end

  # finds which kind of child were started under a global child supervisor
  # (GlobalChild module IS the supervisor)
  def child_kind(gc_parent) do
    case GlobalChild.status(gc_parent) do
      {:actual, _} -> :actual
      :monitor -> :monitor
    end
  end

  def await_down(ref) when is_reference(ref) do
    receive do
      {:DOWN, ^ref, :process, _, _} -> :ok
    end
  end
end
