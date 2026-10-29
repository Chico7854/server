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

## First-time setup on the notebook

1. **Install Ubuntu Server** by following the install guide. This setup runs Nginx inside
   Docker, so if the guide installed Nginx directly on Ubuntu, turn that one off:
   ```bash
   sudo systemctl disable --now nginx
   ```
2. **Clone this repo and install Docker:**
   ```bash
   git clone https://github.com/Chico7854/server.git ~/server
   cd ~/server
   ./scripts/install-docker.sh
   ```
   If the repo is private, `git clone` asks for your GitHub username and a
   [personal access token](https://github.com/settings/tokens) (not your password).
   When the script finishes, **log out and back in** so you can run `docker` without `sudo`.
3. **Start everything:**
   ```bash
   cd ~/server
   docker compose up -d
   ```
   This starts the front door and both tunnels. They all restart on their own after
   a reboot or power cut.
4. **Get the public URLs:**
   ```bash
   ./scripts/urls.sh
   ```
   Open each URL in a browser. The prod one should say `Server is running (prod)`
   and the test one `Server is running (test)`.

To update the server later: `cd ~/server && git pull && docker compose up -d`.

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

## Adding an app

Apps never change this repo. Each app lives in its own private repo and plugs in by
following the contract below.

### The app contract

The server runs any app that follows these rules:

1. **Docker.** The app repo has a `Dockerfile` and a `docker-compose.yml`
   (start from `app-template/docker-compose.yml`).
2. **Name.** The app has a short name using lowercase letters, digits and dashes,
   such as `investment`. It is served at `/<name>/`.
3. **Port 3000.** The container that serves the app listens on port `3000`.
4. **Path prefix.** Requests arrive with the full path, such as `/investment/api/users`.
   The app serves its backend routes and its built frontend under `/<name>/`.
   The `BASE_PATH` environment variable holds that prefix (`/investment`), and the front
   door also sends it in the `X-Forwarded-Prefix` header. Frontend build tools have a
   setting for this (for example `base` in Vite).
5. **Health check.** `GET /<name>/health` returns HTTP 200 when the app is ready.
   The deploy waits for it.
6. **Network name.** The serving container joins the external `web` network with the
   alias `<name>-prod` or `<name>-test`. The template does this for you.
7. **Private repo.** Self-hosted runners must only serve private repos. On a public repo,
   anyone opening a pull request could run code on the notebook.

Each environment of each app is its own Compose project (`investment-prod`,
`investment-test`), so prod and test have separate containers and separate databases.
The template includes an example Postgres database; delete it if the app doesn't need one.

`examples/sample-app/` is a tiny app that follows the contract. It's useful for trying
the setup before a real app exists.

### Connecting an app repo

1. **Copy two files** from `app-template/` into the app repo, keeping their paths:
   `docker-compose.yml` and `.github/workflows/deploy.yml`. In the workflow, set
   `APP_NAME` and replace the placeholder test command.
2. **Add the secrets.** In the app repo on GitHub, open **Settings → Environments** and
   create two environments named exactly `test` and `production`. In each one, add a
   secret named `DOTENV` holding that environment's settings, one per line:
   ```
   POSTGRES_PASSWORD=a-long-random-password
   SOME_API_KEY=...
   ```
   Use different values for test and production. Secrets never go in git.
   Optional: under `production`, turn on **Required reviewers** and add yourself, so a
   production deploy waits for your click.
3. **Register the notebook as a runner** for the app repo. On GitHub, open
   **Settings → Actions → Runners → New self-hosted runner** and copy the token shown
   after `--token` (it expires after an hour). Then on the notebook:
   ```bash
   ~/server/scripts/add-runner.sh Chico7854/<app-repo> <token>
   ```
   The runner starts on boot. Personal GitHub accounts can't share one runner across
   repos, so do this once per app repo. **Only for private repos.**

### Deploy flow

| You do | What happens |
| --- | --- |
| Open a pull request | Tests run on GitHub's machines. Nothing is deployed. |
| Merge or push to `main` | Tests run, then the app deploys to **test**. |
| Push a version tag: `git tag v1.0.0 && git push origin v1.0.0` | Tests run, then that exact commit deploys to **production**. |

Each deploy builds and starts the app, then waits up to 60 seconds for
`/<name>/health`. If the app doesn't answer, the job fails and shows the app's recent
logs in the Actions tab. Afterwards the secrets file is deleted from the notebook and
unused Docker images are removed to save disk space.

**Rolling back production:** in the app repo's **Actions** tab, open the run for an older
tag (for example `v1.0.0`) and click **Re-run all jobs**. That deploys the older version again.

### Trying it with the sample app

Before a real app exists, you can test the whole flow with `examples/sample-app/`:
create a new **private** repo, copy `app.py` and `Dockerfile` from `examples/sample-app/`
plus the two template files into it, set `APP_NAME: sample` in the workflow, and follow
the steps above (the `DOTENV` secret only needs `POSTGRES_PASSWORD=...`). Pushing to
`main` should make `<test-url>/sample/` show `"env": "test"`, and pushing tag `v0.1.0`
should make `<prod-url>/sample/` show `"env": "prod"`.

## Automated tests

Every pull request and every push to `main` runs these on GitHub:

- `tests/routing-test.sh` starts the real front door (without the tunnels, which GitHub
  can't open) with a fake app and checks what visitors and apps see.
- `tests/app-template-test.sh` runs the sample app through the app template as both
  prod and test and checks each one is reachable through the front door, with its own
  containers and database.

You can run them yourself on any machine with Docker, for example `./tests/routing-test.sh`.

## Not set up yet

- **Backups.** Databases are **not** backed up. Add backups before storing data you can't lose.
- **Domain.** URLs are random and change on every restart until a domain is added.

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| `urls.sh` says *not ready yet* | The tunnel is still connecting. Wait 10 seconds and run it again. If it stays that way, check `docker compose logs tunnel-prod` (or `tunnel-test`); a restart with `docker compose restart tunnel-prod` gives it a new URL. |
| `urls.sh` says *tunnel is not running* | Run `docker compose up -d` in `~/server`, then `docker compose ps` to see what's up. |
| Old URL stopped working | The notebook or tunnel restarted, so the URL changed. Run `./scripts/urls.sh` again. |
| `App 'x' is not running in prod` | The app isn't deployed to that environment, or its container stopped. Run `docker ps` and check the app repo's Actions tab. |
| Deploy job stays *Queued* / "Waiting for a runner" | The notebook's runner is offline. Check it with `sudo ~/actions-runners/<app-repo>/svc.sh status` and start it with `sudo ~/actions-runners/<app-repo>/svc.sh start`. |
| Deploy fails at *Wait until healthy* | The app didn't answer `/<name>/health` in 60 s. Read the logs printed in that step. Common causes: wrong `APP_NAME`, app not listening on port 3000, or a missing value in `DOTENV`. |
| `permission denied ... docker.sock` | Your user isn't in the `docker` group yet. Log out and back in after `install-docker.sh`. |

## Manual smoke test

GitHub tests the routing automatically, but the tunnels can only be checked on the
notebook. After setup, or after changing anything here:

- [ ] `docker compose up -d` starts `nginx`, `tunnel-prod` and `tunnel-test` (`docker compose ps`)
- [ ] `./scripts/urls.sh` prints a `prod` and a `test` URL
- [ ] The prod URL shows `Server is running (prod)`, the test URL `Server is running (test)`
- [ ] `<url>/healthz` shows `ok prod` / `ok test`
- [ ] After `sudo reboot`, everything comes back by itself (URLs will be new)
- [ ] `add-runner.sh` registers a runner for the sample app repo, and it shows as *Idle* on GitHub
- [ ] Pushing to `main` in the sample app repo deploys it: `<test-url>/sample/` shows `"env": "test"`
- [ ] Pushing tag `v0.1.0` deploys it to production: `<prod-url>/sample/` shows `"env": "prod"`
