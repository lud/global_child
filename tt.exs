defmodule Child do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_) do
    IO.puts("-- init")
    send(self(), :tick)
    send(self(), :crash)
    # {:ok, 0}
    {:stop, :nope!}
  end

  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, 200)
    IO.puts("tick #{state}")

    if state > 10 do
      {:stop, :normal, state}
    else
      {:noreply, state + 1}
    end
  end

  def handle_info(:crash, state) do
    IO.puts("creash! #{state}")
    Crash.now!()
  end
end

{_, ref} =
  spawn_monitor(fn ->
    Supervisor.start_link([Child], strategy: :one_for_one, max_restarts: 2000, max_seconds: 1)
    |> IO.inspect(label: "sup_started")

    Process.sleep(:infinity)
  end)

receive do
  {:DOWN, ^ref, :process, pid, reason} -> binding() |> IO.inspect(label: "binding()")
end
