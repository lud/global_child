defmodule GlobalChild.NetSplitTest do
  use ExUnit.Case
  alias GlobalChild.Test.Server

  test "run a single process on a three-nodes cluster" do
    nodes = LocalCluster.start_nodes(:simple_run, 3)
    name = {:global, __MODULE__.Run}
    gc_spec = {GlobalChild, debug: true, child: {Server, pingback: self(), name: name}}

    # start the global child on all nodes
    start_supervised_on_nodes(nodes, gc_spec)

    # assert that we receive only one message from the tests servers
    {_, _, node} = assert_receive {:hello_from, _, _}
    assert node in nodes
    refute_receive {:hello_from, _, _}

    [pid1, pid2, pid3] = for n <- nodes, do: get_pid_from(n, name)
    assert pid1 == pid2
    assert pid1 == pid3
  end

  test "global child will run on both nodes if two nodes are disconnected" do
    nodes = [node1, node2] = LocalCluster.start_nodes(:netsplit, 2)
    name = {:global, __MODULE__.Split}
    gc_spec = {GlobalChild, debug: true, child: {Server, name: name}}

    # start the global child on all nodes
    start_supervised_on_nodes(nodes, gc_spec)

    # for now there should be only one child
    assert get_node_from(node1, name) == get_node_from(node2, name)

    # After a netsplit, both nodes should have the child
    Schism.partition([node1])
    Process.sleep(100)

    # the child on each node returns itself
    assert {pid1, ^node1} = rpc(node1, Server, :get_info, [name])
    assert {pid2, ^node2} = rpc(node2, Server, :get_info, [name])
    assert pid1 != pid2
  end

  defp start_supervised_on_nodes(nodes, gc_spec) do
    for n <- nodes do
      {:ok, _} = rpc(n, Supervisor, :start_link, [[gc_spec], [strategy: :one_for_one]])
    end
  end

  defp rpc(node, m, f, a) do
    :rpc.block_call(node, m, f, a)
  end

  defp get_node_from(node, name) do
    case rpc(node, Server, :get_info, [name]) do
      {_, n} -> n
    end
  end

  defp get_pid_from(node, name) do
    case rpc(node, Server, :get_info, [name]) do
      {pid, _} -> pid
    end
  end
end
