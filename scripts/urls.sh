#!/usr/bin/env bash
# Prints the current public URLs of the prod and test tunnels.
# They change every time a tunnel restarts, so run this after a reboot.
set -euo pipefail
cd "$(dirname "$0")/.."

for env in prod test; do
  url=$(docker compose logs "tunnel-$env" 2>/dev/null \
    | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -n 1 || true)
  printf '%-5s %s\n' "$env" "${url:-(not ready yet, try again in a few seconds)}"
done
