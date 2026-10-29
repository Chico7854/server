#!/usr/bin/env bash
# Proves the app contract end to end: runs examples/sample-app through
# app-template/docker-compose.yml as both prod and test, then checks through
# the front door that each environment answers its health check and reaches
# its own instance, with its own containers and database volume.
#
# Usage:  ./tests/app-template-test.sh   (needs Docker)
set -euo pipefail
cd "$(dirname "$0")/.."

APP=sample-template-test
DIR=examples/sample-app
CLIENT=app-template-test-client
failures=0

compose() { # compose <env> <args...>
  local env=$1
  shift
  APP_NAME=$APP APP_ENV=$env docker compose -f app-template/docker-compose.yml --project-directory "$DIR" "$@"
}
cleanup() {
  docker rm -f "$CLIENT" >/dev/null 2>&1 || true
  for env in prod test; do compose "$env" down -v >/dev/null 2>&1 || true; done
  rm -f "$DIR/.env"
}
trap cleanup EXIT

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }
get() { docker exec "$CLIENT" curl -s "$1"; }

echo "Starting the front door and the sample app in prod and test..."
docker compose up -d nginx
# Stands in for the GitHub Environment's DOTENV secret.
printf 'POSTGRES_PASSWORD=template-test-password\n' > "$DIR/.env"
compose prod up -d --build --wait
compose test up -d --build --wait
docker run -d --name "$CLIENT" --network web curlimages/curl:8.17.0 sleep infinity >/dev/null

for env in prod test; do
  port=$([[ $env == prod ]] && echo 8080 || echo 8081)
  ok=
  for _ in $(seq 1 30); do
    [[ $(get "http://nginx:$port/$APP/health") == ok ]] && { ok=1; break; }
    sleep 1
  done
  [[ -n $ok ]] && pass "/$APP/health answers on $env" || fail "/$APP/health answers on $env"
done

prod=$(get "http://nginx:8080/$APP/")
test=$(get "http://nginx:8081/$APP/")
grep -q '"env": "prod"' <<<"$prod" && pass "prod URL reaches the prod instance" || fail "prod URL reaches the prod instance: $prod"
grep -q '"env": "test"' <<<"$test" && pass "test URL reaches the test instance" || fail "test URL reaches the test instance: $test"
grep -q "\"base_path\": \"/$APP\"" <<<"$prod" && pass "BASE_PATH is /$APP" || fail "BASE_PATH is /$APP"

host_of() { grep -o '"hostname": "[^"]*"' <<<"$1"; }
[[ $(host_of "$prod") != "$(host_of "$test")" ]] && pass "prod and test are different containers" || fail "prod and test are different containers"

volumes=$(docker volume ls -q)
if grep -qx "$APP-prod_db-data" <<<"$volumes" && grep -qx "$APP-test_db-data" <<<"$volumes"; then
  pass "prod and test have separate database volumes"
else
  fail "prod and test have separate database volumes (found: $(tr '\n' ' ' <<<"$volumes"))"
fi

echo
if ((failures)); then
  echo "$failures check(s) failed."
  for env in prod test; do compose "$env" logs --tail 30; done
  exit 1
fi
echo "All app template checks passed."
