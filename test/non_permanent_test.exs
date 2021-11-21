defmodule GlobalChild.NonPermanentTest do
  use ExUnit.Case
  import GlobalChild.TestTools
  alias GlobalChild.Test.Server

  test "run a transient global child" do
    nodes = [node1, node2] = LocalCluster.start_nodes(:netsplit, 2)

    gname = __MODULE__.Transient
    name = {:global, gname}

    # The child has a restart :transient definition
    gc_spec = {GlobalChild, child: {Server, restart: :transient, name: name}}

    # start the global child on all nodes
    [sup1, sup2] = start_supervised_on_nodes(nodes, gc_spec)
    sync_nodes(nodes)

    # for now there should be only one child
    assert get_node_from(node1, name) == get_node_from(node2, name)
    assert get_pid_from(node1, name) == get_pid_from(node2, name)
    assert is_pid(get_pid_from(node1, name))

    global_child = get_pid_from(node1, name)

    # We stop the child with a normal reason. As it is transient, it should be
    # down. Also the global child handlers must be down too.
    ref = Process.monitor(global_child)
    assert :ok = GenServer.stop(global_child)
    await_down(ref)

    Process.sleep(100)

    assert :undefined = :global.whereis_name(gname)

    assert [{GlobalChild.Test.Server, :undefined, :supervisor, [GenServer]}] =
             Supervisor.which_children(sup1)

    assert [{GlobalChild.Test.Server, :undefined, :supervisor, [GenServer]}] =
             Supervisor.which_children(sup2)

    # Unfortunately, to restart the child and go back to a running state on all
    # nodes, the child must be restarted on all nodes.  This is left to the
    # library user, for instance by registering the supervisors with an atom
    # name locally.  Here, we know the pids of the supervisors so it is simple.
    assert {:ok, _} = Supervisor.restart_child(sup1, GlobalChild.Test.Server)
    assert {:ok, _} = Supervisor.restart_child(sup2, GlobalChild.Test.Server)

    # We should be back to the original state now
    assert get_node_from(node1, name) == get_node_from(node2, name)
    assert get_pid_from(node1, name) == get_pid_from(node2, name)
    assert is_pid(get_pid_from(node1, name))

    LocalCluster.stop_nodes(nodes)
  end

  test "run a temporary global child" do
    nodes = [node1, node2] = LocalCluster.start_nodes(:netsplit, 2)

    gname = __MODULE__.Temporary
    name = {:global, gname}

    # The child has a restart :temporary definition
    gc_spec = {GlobalChild, child: {Server, restart: :temporary, name: name}}

    # start the global child on all nodes
    [sup1, sup2] = start_supervised_on_nodes(nodes, gc_spec)
    sync_nodes(nodes)

    # for now there should be only one child
    assert get_node_from(node1, name) == get_node_from(node2, name)
    assert get_pid_from(node1, name) == get_pid_from(node2, name)

    global_child = get_pid_from(node1, name)

    # We stop the child with a normal reason. As it is temporary, it should be
    # down. Also the global child handlers must be down too.
    ref = Process.monitor(global_child)
    assert :ok = GenServer.stop(global_child)
    await_down(ref)
    Process.sleep(100)

    assert :undefined = :global.whereis_name(gname)

    assert [] = Supervisor.which_children(sup1)
    assert [] = Supervisor.which_children(sup2)

    LocalCluster.stop_nodes(nodes)
  end
end
