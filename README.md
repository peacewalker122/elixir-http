# MiniHttp

MiniHttp is a hands-on Elixir/OTP project that implements a tiny HTTP/1.1 server
from the ground up. It listens on TCP port 4001, accepts raw socket connections,
parses incoming requests manually, and sends plain-text responses without
depending on common web frameworks such as Plug or Cowboy. The codebase is kept
intentionally small to make it useful for tutorials, workshops, or anyone who
wants to understand the mechanics of building a network service with OTP
primitives.

## Why This Project Exists

- **Education first** – every module is deliberately concise so you can trace
  the supervision tree, request lifecycle, and error handling without wading
  through abstractions.
- **OTP in practice** – it demonstrates how `GenServer`, `Task.Supervisor`, and
  `DynamicSupervisor` collaborate to accept connections safely, recover from
  crashes, and time out long-running requests.
- **Debug-friendly** – the endpoints include predictable payloads for quick
  sanity checks, an echo service for inspecting incoming headers, and an
  intentional delay route to see timeout behaviour in action.

## Architecture Overview

| Component | Location | Responsibility |
| --- | --- | --- |
| `MiniHttp.Application` | `lib/mini_http/application.ex` | Boots the supervision tree and starts the TCP server on port 4001. |
| `MiniHttp.Server` | `lib/mini_http/server.ex` | Listens on the TCP socket, accepts connections, and hands them off to supervised tasks. |
| `MiniHttp.RequestWorker` | `lib/mini_http/request.ex` | Parses the HTTP request, routes it, and writes the response back to the client. |

The server operates one connection per task. Each connection is parsed in a
loop-free flow: read the request line, read headers until a blank line, optionally
read the body, route the request, and send a formatted HTTP response. Timeouts
and crashes are caught so they cannot take down the acceptor loop.

## Requirements

- Elixir 1.12 or newer
- Erlang/OTP compatible with your Elixir installation
- `mix` build tool (installed alongside Elixir)

## Getting Started

1. **Install dependencies**

   ```bash
   mix deps.get
   ```

2. **Start the server**

   ```bash
   mix run --no-halt
   ```

   The server binds to `http://localhost:4001`. Logs appear in the same shell.

   To enable TLS locally, first generate a self-signed certificate (requires
   `openssl`):

   ```bash
   ./scripts/generate_dev_certs.sh
   ```

   Then provide the certificate paths and set the flag:

   ```bash
   MINI_HTTP_TLS=true \
   MINI_HTTP_CERT=priv/cert.pem \
   MINI_HTTP_KEY=priv/key.pem \
   mix run --no-halt
   ```

   When the flag is present the listener switches to HTTPS on the same port.
   Alternatively, copy `.env.example` to `.env`, tweak the values, and the
   application will load them automatically during boot.

3. **Interact from another terminal**

   ```bash
   curl http://localhost:4001/
   curl http://localhost:4001/health
   curl http://localhost:4001/sleep
   curl -X POST http://localhost:4001/echo -d "Hello"
   ```

4. **Stop the server**

   Press `Ctrl+C` twice to shut down the OTP application cleanly.

## Built-in Endpoints

- `GET /` – returns `Hello, World!` and confirms the server is running.
- `GET /health` – returns `OK`; handy for scripts or container probes.
- `GET /sleep` – sleeps for 35 seconds before responding, showcasing timeout
  handling from the acceptor process (the supervising task may be terminated).
- `POST /echo` – echoes the request body and most headers back to the client for
  debugging clients or tooling.
- Any other route results in a `404 Not Found` response with a small payload.

## Implementation Notes

- Requests are read using `:gen_tcp` with `packet: :line` to simplify parsing of
  the request line and headers. Bodies are read explicitly based on the
  `Content-Length` header.
- Responses use a minimal status map to translate numeric codes into standard
  reason phrases.
- Each connection runs in a supervised task; if the request exceeds 30 seconds,
  the task is shut down and the client gets a `408 Request Timeout` response.
- Errors during parsing fall back to safe defaults and attempt to respond with a
  `400` or `500` code before closing the socket.

## Testing

Run the automated test suite with:

```bash
mix test
```

The existing tests cover the baseline project scaffolding. You can extend them
with integration scenarios or property tests as you evolve the server.

## Extending the Server

- Add new routes by updating `request_router/1` in
  `lib/mini_http/request.ex`.
- Experiment with different supervision strategies or connection pools by
  adjusting the children list in `MiniHttp.Application`.
- Swap in `packet: 0` or `active: true` socket modes to explore alternative
  parsing approaches.
- Integrate with observability tools by expanding the Logger usage or emitting
  telemetry events from each request lifecycle stage.

### TLS configuration

- Run `./scripts/generate_dev_certs.sh` to create local self-signed assets in
  `priv/certs`.
- Toggle TLS with the `MINI_HTTP_TLS` environment variable (`true`, `1`, or
  `yes` enable it).
- Supply absolute or relative paths to PEM-encoded files via `MINI_HTTP_CERT`
  and `MINI_HTTP_KEY`.
- Copy `.env.example` to `.env` to manage these variables locally; the loader
  runs before the supervision tree starts.
- Optionally change the listening port with `MINI_HTTP_PORT` (defaults to 4001).
- The application validates the files exist at boot and raises a clear error if
  they are missing.

## Troubleshooting

- **Port already in use** – ensure nothing else binds to 4001 or change the
  `@port` constant in `MiniHttp.Application`.
- **Timeouts on `/sleep`** – this is expected; examine logs for the
  `Request processing timed out` entry to see the OTP supervision in action.
- **Bad Request responses** – malformed requests or incorrect `Content-Length`
  values will yield a `400`; check the raw payload with tools like `nc` to
  inspect what the server receives.

## Contributing

This project is primarily a learning scaffold, so contributions usually take the
form of documentation improvements, new endpoint examples, or additional tests.
Feel free to fork, experiment, and share your own variations.
