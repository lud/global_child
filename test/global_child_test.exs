defmodule GlobalChildTest do
  use ExUnit.Case
  import GlobalChild.TestTools
  alias GlobalChild.Test.Server

  test "test starting a single process" do
    name = {:global, __MODULE__.Single}
    gc_parent = start_supervised!({GlobalChild, child: {Server, name: name}})

    assert {:actual, pid} = GlobalChild.status(gc_parent)

    this_node = node()
    assert {^pid, ^this_node} = Server.get_info(pid)
    assert {^pid, ^this_node} = Server.get_info(name)
    assert pid == :global.whereis_name(__MODULE__.Single)
  end

  test "test starting two processes with different IDs" do
    start_supervised!(%{
      id: :test_sup,
      start:
        {Supervisor, :start_link,
         [
           [
             {GlobalChild, child: {Server, id: :a, name: {:global, __MODULE__.One}}},
             {GlobalChild, child: {Server, id: :b, name: {:global, __MODULE__.Two}}}
           ],
           [strategy: :one_for_one]
         ]}
    })

    this_node = node()
    assert {_, ^this_node} = Server.get_info({:global, __MODULE__.One})
    assert {_, ^this_node} = Server.get_info({:global, __MODULE__.Two})
  end

  test "starting two processes under the same name locally, under different supervisors" do
    {:ok, sup1} =
      Supervisor.start_link(
        [{GlobalChild, child: {Server, name: {:global, __MODULE__}}}],
        strategy: :one_for_one
      )

    Process.sleep(100)

    {:ok, sup2} =
      Supervisor.start_link(
        [{GlobalChild, child: {Server, name: {:global, __MODULE__}}}],
        strategy: :one_for_one
      )

    assert child_child_kind(sup1) == :actual
    assert child_child_kind(sup2) == :monitor

    # Assert that the second child will take over
    GenServer.stop(sup1)
    Process.sleep(100)
    assert child_child_kind(sup2) == :actual
  end
end
