defmodule GlobalChildTest do
  use ExUnit.Case
  doctest GlobalChild

  test "greets the world" do
    assert GlobalChild.hello() == :world
  end
end
