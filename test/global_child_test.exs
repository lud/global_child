defmodule GlobalChildTest do
  use ExUnit.Case
  alias GlobalChild.Test.GS

  test "test starting a single process" do
    sup = start_supervised!({GlobalChild, child: {GS, name: {:global, __MODULE__}}})

    assert [{GS, pid, :worker, [GS]}] = Supervisor.which_children(sup)

    assert node() == GS.get_node(pid)
    assert node() == GS.get_node({:global, __MODULE__})
    assert pid == :global.whereis_name(__MODULE__)
  end
end
