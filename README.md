# server

Shared infrastructure for running my apps on a home notebook with Ubuntu Server.
Every app gets a **production** and a **test** environment.

This repo holds only the infrastructure. Each app lives in its own private repo.

## How it fits together

```
prod entrance ─► nginx:8080 ─┐
test entrance ─► nginx:8081 ─┤
                             ▼
      /investment/...  ─►  container "investment-prod" or "investment-test"
      /other-app/...   ─►  container "other-app-prod"  or "other-app-test"
```

**Nginx** is the front door. It reads the first part of the path (`/investment/`)
and forwards the request to the container named `<app>-prod` or `<app>-test`,
depending on which entrance the visitor came through. It looks apps up at request
time, so this repo never changes when an app is added.

What the front door does:

| Request | Answer |
| --- | --- |
| `/` | `Server is running (prod)` or `(test)` |
| `/healthz` | `ok prod` or `ok test` |
| `/<app>` | Redirects to `/<app>/`, keeping the `?query` |
| `/<app>/...` | Forwarded to `<app>-<env>` on port 3000, with the full path |
| `/<app>/...` when that app isn't running | `502 App '<app>' is not running in <env>.` |

Apps receive the headers `X-Forwarded-Prefix: /<app>`, `X-Forwarded-Proto: https`,
the visitor's IP in `X-Real-IP` / `X-Forwarded-For`, and WebSocket upgrades.
Uploads can be up to 20 MB and requests can take up to 5 minutes.

| What | Where |
| --- | --- |
| Shared services | `docker-compose.yml` |
| Routing rules | `nginx/default.conf`, `nginx/routes.inc` |
| Small example app | `examples/sample-app/` |
| Automated tests | `tests/`, run by `.github/workflows/ci.yml` |

## Starting it

```bash
docker compose up -d
```

Every container restarts on its own after a reboot.

## Automated test

Every pull request and every push to `main` runs `tests/routing-test.sh` on GitHub.
It starts the real front door with a fake app and checks what visitors and apps see.
You can run it yourself on any machine with Docker:

```bash
./tests/routing-test.sh
```
