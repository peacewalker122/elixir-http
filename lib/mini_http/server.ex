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
    {:ok, pid} = Task.Supervisor.start_child(MiniHttp.TaskSupervisor, fn -> serve(client) end)
    :ok = :gen_tcp.controlling_process(client, pid)
    loop_acceptor(socket)
  end

  # the workflow is
  # build the first line first, second parse the header until it met the \r\n line, and last parse the body.

  defp serve(socket) do
    # randomly crashed

    # with {:ok, req} <- parse_request(socket) do
    #   send_response(socket, req)
    # else
    #   err -> err
    # end

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
        [method, target, version] = String.trim_leading(line) |> String.split(" ", parts: 3)

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
        if line == "" || line == "\r\n" do
          {:ok, req}
        else
          [key, value] = String.trim(line) |> String.split(": ", parts: 2)
          req = %{req | headers: Map.put(req.headers, String.downcase(key), value)}
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

    Logger.info("content-length is #{cl}")

    if cl > 0 do
      :ok = :inet.setopts(socket, packet: 0)

      case :gen_tcp.recv(socket, cl) do
        {:ok, body} ->
          {:ok, %{req | body: body, content_length: cl}}

        err ->
          err
      end
    else
      {:ok, req}
    end
  end

  defp parse_request(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, data} ->
        Logger.info("Received data: #{inspect(data)}")
        data_lines = String.split(data, "\r\n")
        [request_line | header_lines] = data_lines

        [method, target, version] = String.split(request_line, " ")

        headers =
          header_lines
          |> Enum.filter(&(&1 != ""))
          |> Enum.map(fn line ->
            [key, value] = String.split(line, ": ", parts: 2)
            {key, value}
          end)
          |> Enum.into(%{})

        content_length =
          headers
          |> Map.get("Content-Length", "0")
          |> String.to_integer()

        req = %{
          method: method,
          target: target,
          version: version,
          headers: headers,
          body: "",
          content_length: content_length
        }

        if content_length > 0 do
          :ok = :inet.setopts(socket, packet: 0)

          case :gen_tcp.recv(socket, content_length) do
            {:ok, body} ->
              {:ok, %{req | body: body}}

            err ->
              err
          end
        else
          {:ok, req}
        end

        {:ok, req}

      err ->
        err
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
