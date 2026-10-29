#!/usr/bin/env bash
# Automated routing test for the front door.
#
# Starts the real front door (tunnels excluded: CI can't open public tunnels),
# plus a fake app built from examples/sample-app that echoes what it receives,
# then sends HTTP requests to the prod and test entrances and checks only what
# a visitor or an app can observe: status codes, bodies, forwarded path and headers.
#
# Usage:  ./tests/routing-test.sh
# Needs Docker. Safe to run on the notebook too: it only adds and removes its
# own "routing-test-*" containers, but it does (re)start the front door.
set -euo pipefail
cd "$(dirname "$0")/.."

CLIENT=routing-test-client
IMAGE=routing-test-sample-app
PROD=http://nginx:8080
TEST=http://nginx:8081
failures=0

cleanup() {
  docker rm -f "$CLIENT" routing-test-fake-prod routing-test-fake-test >/dev/null 2>&1 || true
}
trap cleanup EXIT

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }

# curl from inside the web network. Prints the body, then the status code on the last line.
request() { docker exec "$CLIENT" curl -s -o - -w '\n%{http_code}' "$@"; }
status_of() { tail -n 1 <<<"$1"; }
body_of() { sed '$d' <<<"$1"; }

# expect <description> <status> <text the body must contain> <curl args...>
expect() {
  local desc=$1 want_status=$2 want_text=$3
  shift 3
  local out
  out=$(request "$@")
  if [[ $(status_of "$out") == "$want_status" ]] && grep -qF -- "$want_text" <<<"$(body_of "$out")"; then
    pass "$desc"
  else
    fail "$desc (wanted $want_status containing '$want_text', got:)"
    sed 's/^/          /' <<<"$out"
  fi
}

# wait_for <url> <status>: retry for up to 30 s
wait_for() {
  for _ in $(seq 1 30); do
    [[ $(status_of "$(request "$1")") == "$2" ]] && return 0
    sleep 1
  done
  return 1
}

start_fake() { # start_fake <env>
  docker run -d --name "routing-test-fake-$1" --network web --network-alias "fake-$1" \
    -e BASE_PATH=/fake -e APP_ENV="$1" "$IMAGE" >/dev/null
}

echo "Starting the front door and a fake app..."
docker compose up -d nginx
docker build -q -t "$IMAGE" examples/sample-app >/dev/null
cleanup
docker run -d --name "$CLIENT" --network web curlimages/curl:8.17.0 sleep infinity >/dev/null
start_fake prod
wait_for "$PROD/healthz" 200 || { echo "Front door did not start"; docker compose logs nginx; exit 1; }
wait_for "$PROD/fake/health" 200 || { echo "Fake app did not start"; docker logs routing-test-fake-prod; exit 1; }

echo "Front door pages"
expect "prod / says running (prod)" 200 "Server is running (prod)" "$PROD/"
expect "test / says running (test)" 200 "Server is running (test)" "$TEST/"
expect "prod /healthz" 200 "ok prod" "$PROD/healthz"
expect "test /healthz" 200 "ok test" "$TEST/healthz"

echo "Forwarding to an app"
headers=(-H 'Host: visitor.example' -H 'CF-Connecting-IP: 203.0.113.7')
expect "full path and query reach the app" 200 '"path": "/fake/some/path?x=1"' "${headers[@]}" "$PROD/fake/some/path?x=1"
expect "prod entrance reaches the prod app" 200 '"env": "prod"' "$PROD/fake/"
expect "X-Forwarded-Prefix" 200 '"x-forwarded-prefix": "/fake"' "$PROD/fake/"
expect "X-Forwarded-Proto is https" 200 '"x-forwarded-proto": "https"' "$PROD/fake/"
expect "original Host is kept" 200 '"host": "visitor.example"' "${headers[@]}" "$PROD/fake/"
expect "X-Real-IP from Cloudflare" 200 '"x-real-ip": "203.0.113.7"' "${headers[@]}" "$PROD/fake/"
expect "X-Forwarded-For from Cloudflare" 200 '"x-forwarded-for": "203.0.113.7"' "${headers[@]}" "$PROD/fake/"
ws=(-H 'Upgrade: websocket' -H 'Connection: Upgrade')
expect "WebSocket Upgrade header" 200 '"upgrade": "websocket"' "${ws[@]}" "$PROD/fake/socket"
expect "WebSocket Connection header" 200 '"connection": "upgrade"' "${ws[@]}" "$PROD/fake/socket"

echo "Redirect without trailing slash"
out=$(docker exec "$CLIENT" curl -s -o /dev/null -D - "$PROD/fake?x=1" | tr -d '\r')
if grep -q '^HTTP/1.1 301' <<<"$out" && grep -qi '^location: /fake/?x=1$' <<<"$out"; then
  pass "/fake?x=1 -> 301 Location: /fake/?x=1"
else
  fail "/fake?x=1 redirect, got:"; sed 's/^/          /' <<<"$out"
fi

echo "Upload size limit"
upload() { # upload <bytes> -> status code
  docker exec "$CLIENT" sh -c "head -c $1 /dev/zero | curl -s -o /dev/null -w '%{http_code}' --data-binary @- $PROD/fake/upload"
}
[[ $(upload 19000000) == 200 ]] && pass "19 MB upload is accepted" || fail "19 MB upload is accepted"
[[ $(upload 21000000) == 413 ]] && pass "21 MB upload is rejected with 413" || fail "21 MB upload is rejected with 413"

echo "Missing apps"
expect "test has no fake app yet -> 502" 502 "App 'fake' is not running in test." "$TEST/fake/"
expect "unknown app -> 502" 502 "App 'nope' is not running in prod." "$PROD/nope/"

echo "Apps are discovered without restarting the front door"
start_fake test
if wait_for "$TEST/fake/health" 200; then
  pass "fake-test became reachable"
  expect "test entrance reaches the test app" 200 '"env": "test"' "$TEST/fake/"
  expect "prod entrance still reaches the prod app" 200 '"env": "prod"' "$PROD/fake/"
else
  fail "fake-test became reachable within 30 s"
fi

echo
if ((failures)); then
  echo "$failures check(s) failed."
  docker compose logs --tail 30 nginx
  exit 1
fi
echo "All routing checks passed."
