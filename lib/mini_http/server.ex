defmodule MiniHttp.Server do
  require Logger

  def accept(port) do
    {:ok, socket} =
      :gen_tcp.listen(port, [:binary, packet: :line, active: false, reuseaddr: true])

    Logger.info("Slowly accepting the fact that this app connect onto port #{port}")
    loop_acceptor(socket)
  end

  defp loop_acceptor(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    Task.start(fn -> serve(client) end)
    loop_acceptor(socket)
  end

  # the workflow is
  # build the first line first, second parse the header until it met the \r\n line, and last parse the body.

  defp serve(socket) do
    with {:ok, req} <- parse_request_line(socket),
         {:ok, req} <- parse_header_line(socket, req),
         {:ok, req} <- parse_body(socket, req) do
      send_response(socket, req)
    else
      err -> err
    end
  end

  defp parse_request_line(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, line} ->
        [method, target, version] = line |> String.split(" ", parts: 3)

        req = %{
          method: method,
          target: target,
          version: version,
          headers: %{},
          body: "",
          content_length: 0
        }

        {:ok, req}

      err ->
        err
    end
  end

  defp parse_header_line(socket, req) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, line} ->
        Logger.info("retrieve header #{line}")

        if line == "" || line == "\r\n" do
          {:ok, req}
        else
          [key, value] = line |> String.split(":", parts: 2)
          req = %{req | headers: Map.put(req.headers, key, value)}
          Logger.info("updating current headers with #{inspect(req.headers)}")
          parse_header_line(socket, req)
        end
    end
  end

  defp parse_body(socket, req = %{headers: headers}) do
    cl =
      headers
      |> Map.get("content-length", "0")
      |> String.to_integer()

    req = %{req | content_length: cl}

    if cl == 0 do
      {:ok, req}
    else
      :ok = :inet.setopts(socket, packet: 0)

      case :gen_tcp.recv(socket, cl) do
        {:ok, bin} ->
          {:ok, %{req | body: bin}}

        err ->
          err
      end
    end
  end

  defp send_response(sock, req) do
    payload =
      [
        # TODO: generate something like markov chain to this.
        "method=#{req.method}",
        "target=#{req.target}",
        "version=#{req.version}",
        "headers=#{inspect(req.headers)}",
        "body=#{inspect(req.body)}"
      ]
      |> Enum.join("\n")

    resp =
      [
        "HTTP/1.1 200 OK\r\n",
        "Content-Type: text/plain\r\n",
        "Content-Length: #{byte_size(payload)}\r\n",
        "Connection: close\r\n",
        "\r\n",
        payload
      ]

    :gen_tcp.send(sock, resp)
  end
end
