defmodule GlobalChild.NetSplitTest do
  alias GlobalChild.Test.Server
  use ExUnit.Case
  import GlobalChild.TestTools

  test "run a single process on a three-nodes cluster" do
    nodes = LocalCluster.start_nodes(:simple_run, 3)

    name = {:global, __MODULE__.Run}
    gc_spec = {GlobalChild, child: {Server, pingback: self(), name: name}}

    # start the global child on all nodes
    start_supervised_on_nodes(nodes, gc_spec)

    # assert that we receive only one message from the tests servers
    {_, _, node} = assert_receive {:hello_from, _, _}
    assert node in nodes
    refute_receive {:hello_from, _, _}

    [pid1, pid2, pid3] = for n <- nodes, do: get_pid_from(n, name)
    assert pid1 == pid2
    assert pid1 == pid3

    LocalCluster.stop_nodes(nodes)
  end

  test "global child will run on both nodes if two nodes are disconnected" do
    nodes = [node1, node2] = LocalCluster.start_nodes(:netsplit, 2)

    gname = __MODULE__.Split
    name = {:global, gname}
    gc_spec = {GlobalChild, child: {Server, name: name}}

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
    assert pid1 == rpc(node1, :global, :whereis_name, [gname])
    assert pid2 == rpc(node2, :global, :whereis_name, [gname])

    # Now we heal the nodes and there should be only one global child left
    heal_sync(nodes)

    # for some reason, global synchronization is slow with those tests. On my
    # dev machine, sleeping for 1000 is never enough for the name conflict to be
    # triggered, whil sleeping for 1150 (+50) always work. If feels strange that
    # the delay is so consistent.
    # # Process.sleep(1500)
    # Instead of sleeping we will just force the synchronization
    assert [:ok, :ok] = rpc_all(nodes, :global, :sync, [])

    global_child = :global.whereis_name(gname)
    assert global_child == rpc(node1, :global, :whereis_name, [gname])
    assert global_child == rpc(node2, :global, :whereis_name, [gname])

    found_1 = rpc(node1, :global, :whereis_name, [gname])
    found_2 = rpc(node2, :global, :whereis_name, [gname])
    assert found_1 == found_2

    info1 = rpc(node1, Server, :get_info, [name])
    info2 = rpc(node2, Server, :get_info, [name])
    assert info1 == info2

    LocalCluster.stop_nodes(nodes)
  end

  test "large netsplit healing still results in a single child" do
    nodes = LocalCluster.start_nodes(:netsplit, 10)

    {left_nodes, right_nodes} = Enum.split(nodes, 4)

    in_left = hd(left_nodes)
    in_right = hd(right_nodes)
    gname = __MODULE__.LargeSplit
    name = {:global, gname}
    gc_spec = {GlobalChild, child: {Server, name: name}}

    start_supervised_on_nodes(nodes, gc_spec)

    assert get_node_from(in_left, name) == get_node_from(in_right, name)

    Schism.partition(left_nodes)
    Process.sleep(100)

    assert {pid1, left_winner} = rpc(in_left, Server, :get_info, [name])
    assert {pid2, right_winner} = rpc(in_right, Server, :get_info, [name])
    assert pid1 != pid2
    assert left_winner != right_winner
    assert pid1 == rpc(in_left, :global, :whereis_name, [gname])
    assert pid2 == rpc(in_right, :global, :whereis_name, [gname])

    heal_sync(nodes)

    global_child = :global.whereis_name(gname)
    assert global_child == rpc(in_left, :global, :whereis_name, [gname])
    assert global_child == rpc(in_right, :global, :whereis_name, [gname])

    found_1 = rpc(in_left, :global, :whereis_name, [gname])
    found_2 = rpc(in_right, :global, :whereis_name, [gname])
    assert found_1 == found_2

    info1 = rpc(in_left, Server, :get_info, [name])
    info2 = rpc(in_right, Server, :get_info, [name])
    assert info1 == info2

    LocalCluster.stop_nodes(nodes)
  end
end
