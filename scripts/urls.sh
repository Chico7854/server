#!/usr/bin/env bash
# Prints the current public URLs of the prod and test tunnels.
# They change every time a tunnel restarts, so run this after a reboot.
set -euo pipefail
cd "$(dirname "$0")/.."

for env in prod test; do
  if [[ -z $(docker compose ps -q --status running "tunnel-$env" 2>/dev/null) ]]; then
    printf '%-5s %s\n' "$env" "(tunnel is not running, start it with: docker compose up -d)"
    continue
  fi
  # A restarted container keeps its old log lines, so take the last URL printed.
  url=$(docker compose logs --no-log-prefix "tunnel-$env" 2>/dev/null \
    | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -n 1 || true)
  printf '%-5s %s\n' "$env" "${url:-(not ready yet, try again in a few seconds)}"
done
