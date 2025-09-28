defmodule MiniHttp.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @port 4001

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: MiniHttp.Worker.start_link(arg)
      # {MiniHttp.Worker, arg}
      {Task, fn -> MiniHttp.Server.accept(@port) end}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MiniHttp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
