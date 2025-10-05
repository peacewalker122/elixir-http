defmodule MiniHttp.RequestWorker do
  use Agent

  @type transport :: :gen_tcp | :ssl
  @type request :: %{
          method: String.t(),
          target: String.t(),
          version: String.t(),
          headers: %{String.t() => String.t()},
          body: binary(),
          content_length: integer()
        }

  @status_messages %{
    100 => "Continue",
    101 => "Switching Protocols",
    200 => "OK",
    201 => "Created",
    202 => "Accepted",
    203 => "Non-Authoritative Information",
    204 => "No Content",
    205 => "Reset Content",
    206 => "Partial Content",
    300 => "Multiple Choices",
    301 => "Moved Permanently",
    302 => "Found",
    303 => "See Other",
    304 => "Not Modified",
    305 => "Use Proxy",
    307 => "Temporary Redirect",
    400 => "Bad Request",
    401 => "Unauthorized",
    402 => "Payment Required",
    403 => "Forbidden",
    404 => "Not Found",
    405 => "Method Not Allowed",
    406 => "Not Acceptable",
    407 => "Proxy Authentication Required",
    408 => "Request Timeout",
    409 => "Conflict",
    410 => "Gone",
    411 => "Length Required",
    412 => "Precondition Failed",
    413 => "Payload Too Large",
    414 => "URI Too Long",
    415 => "Unsupported Media Type",
    416 => "Range Not Satisfiable",
    417 => "Expectation Failed",
    426 => "Upgrade Required",
    500 => "Internal Server Error",
    501 => "Not Implemented",
    502 => "Bad Gateway",
    503 => "Service Unavailable",
    504 => "Gateway Timeout",
    505 => "HTTP Version Not Supported"
  }

  @doc """
  Handle a single HTTP request on the given socket.
  """
  def serve(socket, transport \\ :gen_tcp) do
    # :timer.sleep(1000..2000 |> Enum.random())

    with :ok <- ensure_handshake(socket, transport),
         {:ok, req} <- parse_request_line(socket, transport),
         {:ok, req} <- request_router(req),
         {:ok, req} <- parse_header_line(socket, req, transport),
         {:ok, req} <- parse_body(socket, req, transport) do
      send_response(socket, req, 200, transport)
    else
      {req, :error, status} ->
        send_response(socket, req, status, transport)
        req

      {:handshake_error, reason} ->
        IO.puts("TLS handshake failed: #{inspect(reason)}")
        close_socket(transport, socket)
        {:error, reason}

      {:error, reason} ->
        IO.puts("Failed to parse request: #{inspect(reason)}")

        err = %{
          method: "GET",
          target: "/",
          version: "HTTP/1.1",
          headers: %{},
          body: "Bad Request",
          content_length: byte_size("Bad Request")
        }

        send_response(socket, err, 400, transport)
        err

      _err ->
        err = %{
          method: "GET",
          target: "/",
          version: "HTTP/1.1",
          headers: %{},
          body: "Internal Server Error",
          content_length: byte_size("Internal Server Error")
        }

        send_response(socket, err, 500, transport)
        err
    end
  end

  defp ensure_handshake(_socket, :gen_tcp), do: :ok

  defp ensure_handshake(socket, :ssl) do
    case :ssl.handshake(socket) do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, reason} -> {:handshake_error, reason}
    end
  end

  defp parse_request_line(socket, transport) do
    case recv(transport, socket, 0) do
      {:ok, line} ->
        [method, target, version] = String.trim_leading(line) |> String.split(" ", parts: 3)

        req = %{
          method: method,
          target: target,
          version: version,
          headers: %{},
          body: <<>>,
          content_length: 0
        }

        {:ok, req}

      {_err, reason} ->
        {:error, reason}
    end
  end

  defp parse_header_line(socket, req, transport) do
    case recv(transport, socket, 0) do
      {:ok, line} ->
        if line == "" || line == "\r\n" do
          {:ok, req}
        else
          [key, value] = String.trim(line) |> String.split(": ", parts: 2)
          req = %{req | headers: Map.put(req.headers, String.downcase(key), value)}
          parse_header_line(socket, req, transport)
        end

      {_err, reason} ->
        {:error, reason}
    end
  end

  defp parse_body(socket, req = %{headers: headers}, transport) do
    cl =
      headers
      |> Map.get("content-length", "0")
      |> String.to_integer()

    if cl > 0 do
      case setopts(transport, socket, packet: 0) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end

      case recv(transport, socket, cl) do
        {:ok, body} ->
          {:ok, %{req | body: body, content_length: cl}}

        {_err, reason} ->
          {:error, reason}
      end
    else
      {:ok, req}
    end
  end

  defp request_router(%{method: "GET", target: "/"} = req) do
    %{req | body: "Hello, World!", content_length: byte_size("Hello, World!")}

    {:ok, req}
  end

  defp request_router(%{method: "GET", target: "/health"} = req) do
    %{req | body: "OK", content_length: byte_size("OK")}

    {:ok, req}
  end

  defp request_router(%{method: "GET", target: "/sleep"} = req) do
    :timer.sleep(35000)
    %{req | body: "Slept for 35 seconds", content_length: byte_size("Slept for 5 seconds")}

    {:ok, req}
  end

  defp request_router(%{method: "POST", target: "/echo"} = req) do
    %{req | body: req.body, content_length: byte_size(req.body), headers: req.headers}

    {:ok, req}
  end

  defp request_router(req) do
    {req, :error, 404}
  end

  @spec send_response(:gen_tcp.socket() | :ssl.sslsocket(), request(), integer(), transport()) ::
          :ok
  def send_response(sock, req, status \\ 200, transport \\ :gen_tcp) do
    headers = req.headers

    content_type = Map.get(headers, "content-type", "text/plain")
    content_length = byte_size(req.body)
    status_message = Map.get(@status_messages, status, "Unknown")

    resp =
      [
        "HTTP/1.1 #{status} #{status_message}\r\n",
        "Content-Type: #{content_type}\r\n",
        "Content-Length: #{content_length}\r\n",
        "Connection: close\r\n",
        "\r\n",
        req.body
      ]

    with :ok <- transport_send(transport, sock, resp) do
      close_socket(transport, sock)
    else
      {:error, reason} ->
        IO.puts("Failed to send response: #{inspect(reason)}")
        close_socket(transport, sock)
    end
  end

  defp recv(:ssl, socket, length), do: :ssl.recv(socket, length)
  defp recv(:gen_tcp, socket, length), do: :gen_tcp.recv(socket, length)

  defp transport_send(:ssl, socket, data), do: :ssl.send(socket, data)
  defp transport_send(:gen_tcp, socket, data), do: :gen_tcp.send(socket, data)

  defp close_socket(:ssl, socket), do: :ssl.close(socket)
  defp close_socket(:gen_tcp, socket), do: :gen_tcp.close(socket)

  defp setopts(:ssl, socket, opts), do: :ssl.setopts(socket, opts)
  defp setopts(:gen_tcp, socket, opts), do: :inet.setopts(socket, opts)
end
