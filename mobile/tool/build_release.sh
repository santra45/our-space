#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

env_file="../.env"
if [[ ! -f "$env_file" ]]; then
  echo "Missing $env_file. It needs VITE_MAILBOX_URL and VITE_MAILBOX_TOKEN." >&2
  exit 1
fi

read_env() {
  grep -E "^$1=" "$env_file" | tail -n 1 | cut -d= -f2- | tr -d '\r' | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"
}

url="$(read_env VITE_MAILBOX_URL || true)"
token="$(read_env VITE_MAILBOX_TOKEN || true)"
if [[ -z "$url" || -z "$token" ]]; then
  echo "VITE_MAILBOX_URL and VITE_MAILBOX_TOKEN must both be set in $env_file." >&2
  exit 1
fi

flutter build apk --release --split-per-abi --target-platform android-arm64 \
  --dart-define="VITE_MAILBOX_URL=$url" \
  --dart-define="VITE_MAILBOX_TOKEN=$token" \
  "$@"
