defmodule MiniHttp.Server do
  require Logger

  use GenServer

  @tcp_opts [:binary, packet: :line, active: false, reuseaddr: true]

  # client API
  def start_link(port) do
    GenServer.start_link(__MODULE__, port, name: __MODULE__)
  end

  # server (callbacks)
  @impl true
  def init(port) do
    {:ok, socket} =
      :gen_tcp.listen(port, @tcp_opts)

    # loop_acceptor(socket)
    send(self(), :accept)
    {:ok, socket}
  end

  @impl true
  def handle_info(:accept, socket) do
    case :gen_tcp.accept(socket) do
      {:ok, client} ->
        task =
          Task.Supervisor.async_nolink(
            MiniHttp.TaskSupervisor,
            fn ->
              MiniHttp.RequestWorker.serve(client)
            end
          )

        with :ok <- :gen_tcp.controlling_process(client, task.pid) do
          # wait up to 30 seconds for the request to be processed
          try do
            Task.await(task, 30_000)
          catch
            :exit, _reason ->
              Logger.error("Request processing timed out")

              MiniHttp.RequestWorker.send_response(
                client,
                %{
                  method: "GET",
                  target: "/",
                  version: "HTTP/1.1",
                  headers: %{},
                  body: "Request Timeout\n",
                  content_length: byte_size("Request Timeout")
                },
                408
              )

              :gen_tcp.close(client)

              # kill the task if it's still running
              Task.shutdown(task, :brutal_kill)
          end
        else
          {:error, :badarg} ->
            Logger.error(
              "Failed to set controlling process: badarg, likely the socket is already closed"
            )

            MiniHttp.RequestWorker.send_response(
              client,
              %{
                method: "GET",
                target: "/",
                version: "HTTP/1.1",
                headers: %{},
                body: "",
                content_length: 0
              },
              500
            )

          err ->
            Logger.error("Failed to set controlling process: #{inspect(err)}")
        end

      {:error, reason} ->
        Logger.error("Failed to accept connection: #{inspect(reason)}")
    end

    send(self(), :accept)
    {:noreply, socket}
  end
end
