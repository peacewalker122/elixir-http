defmodule MiniHttp.Server do
  require Logger

  use GenServer

  @tcp_opts [:binary, packet: :line, active: false, reuseaddr: true]

  # client API
  def start_link(opts) do
    GenServer.start_link(__MODULE__, normalize_opts(opts), name: __MODULE__)
  end

  # server (callbacks)
  @impl true
  def init(opts) do
    with {:ok, listener, transport} <- open_listener(opts) do
      state = %{listener: listener, transport: transport, opts: opts}

      send(self(), :accept)
      {:ok, state}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_info(:accept, state) do
    case accept_connection(state) do
      {:ok, client} ->
        task =
          Task.Supervisor.async_nolink(
            MiniHttp.TaskSupervisor,
            fn ->
              MiniHttp.RequestWorker.serve(client, state.transport)
            end
          )

        with :ok <- controlling_process(state.transport, client, task.pid) do
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
                408,
                state.transport
              )

              close_socket(state.transport, client)

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
              500,
              state.transport
            )

            close_socket(state.transport, client)

          err ->
            Logger.error("Failed to set controlling process: #{inspect(err)}")
            close_socket(state.transport, client)
        end

      {:error, reason} ->
        Logger.error("Failed to accept connection: #{inspect(reason)}")
    end

    send(self(), :accept)
    {:noreply, state}
  end

  defp normalize_opts(%{port: port} = opts) when is_integer(port) do
    Map.merge(%{tls?: false, certfile: nil, keyfile: nil}, opts)
  end

  defp normalize_opts(port) when is_integer(port) do
    %{port: port, tls?: false, certfile: nil, keyfile: nil}
  end

  defp open_listener(%{tls?: true, port: port, certfile: cert, keyfile: key}) do
    certfile = require_file(cert, "MINI_HTTP_CERT")
    keyfile = require_file(key, "MINI_HTTP_KEY")

    opts = @tcp_opts ++ [certfile: certfile, keyfile: keyfile]

    case :ssl.listen(port, opts) do
      {:ok, socket} -> {:ok, socket, :ssl}
      {:error, reason} -> {:error, reason}
    end
  end

  defp open_listener(%{port: port}) do
    case :gen_tcp.listen(port, @tcp_opts) do
      {:ok, socket} -> {:ok, socket, :gen_tcp}
      {:error, reason} -> {:error, reason}
    end
  end

  defp require_file(nil, env_name) do
    raise ArgumentError,
          "TLS enabled but #{env_name} is not set. Provide a path to the certificate/key file."
  end

  defp require_file(path, _env_name) do
    case File.exists?(path) do
      true -> path
      false -> raise ArgumentError, "TLS file not found at #{inspect(path)}"
    end
  end

  defp accept_connection(%{transport: :ssl, listener: socket}) do
    :ssl.transport_accept(socket)
  end

  defp accept_connection(%{transport: :gen_tcp, listener: socket}) do
    :gen_tcp.accept(socket)
  end

  defp controlling_process(:ssl, socket, pid) do
    :ssl.controlling_process(socket, pid)
  end

  defp controlling_process(:gen_tcp, socket, pid) do
    :gen_tcp.controlling_process(socket, pid)
  end

  defp close_socket(:ssl, socket) do
    :ssl.close(socket)
  end

  defp close_socket(:gen_tcp, socket) do
    :gen_tcp.close(socket)
  end
end
