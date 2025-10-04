defmodule MiniHttp.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: MiniHttp.TaskSupervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: MiniHttp.DynamicSupervisor},
      {MiniHttp.Server, server_options()}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MiniHttp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp server_options do
    %{
      port: port(),
      tls?: tls_enabled?(),
      certfile: System.get_env("MINI_HTTP_CERT"),
      keyfile: System.get_env("MINI_HTTP_KEY")
    }
  end

  defp port do
    System.get_env("MINI_HTTP_PORT")
    |> case do
      nil -> 4001
      value -> String.to_integer(value)
    end
  end

  defp tls_enabled? do
    System.get_env("MINI_HTTP_TLS", "false")
    |> String.downcase()
    |> case do
      "true" -> true
      "1" -> true
      "yes" -> true
      _ -> false
    end
  end
end
