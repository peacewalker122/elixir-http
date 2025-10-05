#!/usr/bin/env bash
set -euo pipefail

CERT_DIR="$(dirname "$0")/../priv/certs"
CERT_FILE="$CERT_DIR/mini_http_dev.crt"
KEY_FILE="$CERT_DIR/mini_http_dev.key"

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required to generate development certificates" >&2
  exit 1
fi

mkdir -p "$CERT_DIR"

if [[ -f "$CERT_FILE" || -f "$KEY_FILE" ]]; then
  echo "Development TLS assets already exist at $CERT_DIR" >&2
  exit 0
fi

openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout "$KEY_FILE" \
  -out "$CERT_FILE" \
  -days 365 \
  -subj "/CN=localhost"

echo "Generated development certificate: $CERT_FILE"
echo "Generated development private key: $KEY_FILE"
echo "Set MINI_HTTP_TLS=true MINI_HTTP_CERT=$CERT_FILE MINI_HTTP_KEY=$KEY_FILE to enable HTTPS."
