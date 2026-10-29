# server

Shared infrastructure for running my apps on a home notebook with Ubuntu Server.
Every app gets a **production** and a **test** environment, both reachable from the
internet through free Cloudflare tunnels, with no ports opened on the router.

This repo holds only the infrastructure. Each app lives in its own private repo.

## How it fits together

```
visitor ─► https://<random>.trycloudflare.com ─► tunnel-prod ─► nginx:8080 ─┐
visitor ─► https://<random>.trycloudflare.com ─► tunnel-test ─► nginx:8081 ─┤
                                                                            ▼
                       /investment/...  ─►  container "investment-prod" or "investment-test"
                       /other-app/...   ─►  container "other-app-prod"  or "other-app-test"
```

**tunnel-prod / tunnel-test** are Cloudflare quick tunnels. Each one gets a random
public HTTPS address that **changes every time it restarts**. Nothing is published on
the notebook's ports, so the router and firewall stay closed.

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
| Helper scripts | `scripts/` |
| Routing rules | `nginx/default.conf`, `nginx/routes.inc` |
| Small example app | `examples/sample-app/` |
| Automated tests | `tests/`, run by `.github/workflows/ci.yml` |

## Starting it

```bash
docker compose up -d
```

Every container restarts on its own after a reboot.

## Finding the URLs

The tunnel URLs change whenever the notebook reboots or a tunnel restarts. SSH in and run:

```bash
~/server/scripts/urls.sh
```

```
prod  https://some-random-words.trycloudflare.com
test  https://other-random-words.trycloudflare.com
```

If a line says *not ready yet*, the tunnel is still connecting: wait a few seconds and
run it again. Apps are under a path on each URL, for example `https://<prod-url>/investment/`.

Buying a domain later gives fixed URLs. Only the two tunnel services in
`docker-compose.yml` need to change; apps and routing stay the same.

## Automated test

Every pull request and every push to `main` runs `tests/routing-test.sh` on GitHub.
It starts the real front door (without the tunnels, which GitHub can't open) with a fake app and checks what visitors and apps see.
You can run it yourself on any machine with Docker:

```bash
./tests/routing-test.sh
```
