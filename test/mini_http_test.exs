defmodule MiniHttpTest do
  use ExUnit.Case
  doctest MiniHttp

  test "greets the world" do
    assert MiniHttp.hello() == :world
  end
end
