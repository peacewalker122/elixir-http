defmodule MiniHttp.RequestWorker do
  use Agent

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
  def serve(socket) do
    # :timer.sleep(1000..2000 |> Enum.random())

    with {:ok, req} <- parse_request_line(socket),
         {:ok, req} <- parse_header_line(socket, req),
         {:ok, req} <- parse_body(socket, req) do
      send_response(socket, req)
    else
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

        send_response(socket, err, 400)
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

        send_response(socket, err, 500)
        err
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
          body: <<>>,
          content_length: 0
        }

        {:ok, req}

      {_err, reason} ->
        {:error, reason}
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
          parse_header_line(socket, req)
        end

      {_err, reason} ->
        {:error, reason}
    end
  end

  defp parse_body(socket, req = %{headers: headers}) do
    cl =
      headers
      |> Map.get("content-length", "0")
      |> String.to_integer()

    if cl > 0 do
      case :inet.setopts(socket, packet: 0) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end

      case :gen_tcp.recv(socket, cl) do
        {:ok, body} ->
          {:ok, %{req | body: body, content_length: cl}}

        {_err, reason} ->
          {:error, reason}
      end
    else
      {:ok, req}
    end
  end

  @spec send_response(:gen_tcp.socket(), request(), integer()) :: :ok
  def send_response(sock, req, status \\ 200) do
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

    with :ok <- :gen_tcp.send(sock, resp) do
      :gen_tcp.close(sock)
    else
      {:error, reason} ->
        IO.puts("Failed to send response: #{inspect(reason)}")
        :gen_tcp.close(sock)
    end
  end
end
