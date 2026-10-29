# server

Shared infrastructure for running my apps on a home notebook with Ubuntu Server.
Every app gets a **production** and a **test** environment, both reachable from the
internet through free Cloudflare tunnels, with no ports opened on the router.

This repo holds only the infrastructure. Each app lives in its own private repo and
deploys itself here (see [Adding an app](#adding-an-app)).

## How it fits together

```
visitor ─► https://<random>.trycloudflare.com ─► tunnel-prod ─► nginx:8080 ─┐
visitor ─► https://<random>.trycloudflare.com ─► tunnel-test ─► nginx:8081 ─┤
                                                                            ▼
                       /investment/...  ─►  container "investment-prod" or "investment-test"
                       /other-app/...   ─►  container "other-app-prod"  or "other-app-test"
```

- **Nginx** is the front door. It reads the first part of the path (`/investment/`)
  and forwards the request to the container named `<app>-prod` or `<app>-test`,
  depending on which tunnel the visitor came through. It finds apps automatically,
  so this repo never changes when an app is added.
- **tunnel-prod / tunnel-test** are Cloudflare quick tunnels. Each one gets a random
  public HTTPS address that **changes every time it restarts**.
- **Self-hosted GitHub runners** on the notebook run each app's deploy jobs.

| What | Where |
| --- | --- |
| Shared services | `docker-compose.yml` |
| Routing rules | `nginx/default.conf`, `nginx/routes.inc` |
| Helper scripts | `scripts/` |
| Files to copy into a new app repo | `app-template/` |

## First-time setup on the notebook

1. Install Ubuntu Server (follow the install guide). This setup runs Nginx in Docker,
   so if the guide installed Nginx directly on Ubuntu you can turn that one off with
   `sudo systemctl disable --now nginx`.
2. Clone this repo and install Docker:
   ```bash
   git clone https://github.com/Chico7854/server.git ~/server
   cd ~/server
   ./scripts/install-docker.sh
   ```
   Log out and back in so you can run `docker` without `sudo`.
3. Start everything:
   ```bash
   cd ~/server
   docker compose up -d
   ```
   All containers restart on their own after a reboot.
4. Get the public URLs:
   ```bash
   ./scripts/urls.sh
   ```
   Opening either URL should show `Server is running (prod)` or `(test)`.

## Finding the URLs

The tunnel URLs change whenever the notebook reboots or a tunnel restarts. SSH in and run:

```bash
~/server/scripts/urls.sh
```

```
prod  https://some-random-words.trycloudflare.com
test  https://other-random-words.trycloudflare.com
```

Apps are under a path on each URL, for example `https://<prod-url>/investment/`.
Buying a domain later gives fixed URLs; only the tunnel services in `docker-compose.yml`
need to change.

## Adding an app

### The app contract

The server will run any app that follows these rules:

1. **Docker.** The app repo has a `Dockerfile` and a `docker-compose.yml`
   (start from `app-template/docker-compose.yml`).
2. **Name.** The app has a short name using lowercase letters, digits and dashes,
   such as `investment`. It is served at `/<name>/`.
3. **Port 3000.** The container that serves the app listens on port `3000`.
4. **Path prefix.** Requests arrive with the full path, such as `/investment/api/users`.
   The app must serve its backend routes and its built frontend under
   `/<name>/`. The `BASE_PATH` environment variable holds that prefix, and Nginx also
   sends it in the `X-Forwarded-Prefix` header. Frontend build tools have a setting for
   this (for example `base` in Vite).
5. **Health check.** `GET /<name>/health` returns HTTP 200 when the app is ready.
   The deploy waits for it.
6. **Network name.** The serving container joins the external `web` network with the
   alias `<name>-prod` or `<name>-test`. The template does this for you.
7. **Private repo.** Self-hosted runners must only serve private repos. On a public repo,
   anyone opening a pull request could run code on the notebook.

Each environment of each app is its own Compose project (`investment-prod`,
`investment-test`), so prod and test have separate containers and separate databases.

### Steps

1. Copy `app-template/docker-compose.yml` and `app-template/.github/workflows/deploy.yml`
   into the app repo. Set `APP_NAME` in the workflow and replace the placeholder test
   command.
2. In the app repo on GitHub, go to **Settings → Environments** and create two
   environments: `test` and `production`. In each one, add a secret named `DOTENV`
   holding that environment's variables, one per line:
   ```
   POSTGRES_PASSWORD=a-long-random-password
   SOME_API_KEY=...
   ```
   Use different values for test and production. Under `production` you can also turn on
   **Required reviewers** so a prod deploy waits for your click.
3. Register the notebook as a runner for the app repo. On GitHub, open
   **Settings → Actions → Runners → New self-hosted runner** and copy the token shown
   after `--token`. Then on the notebook:
   ```bash
   ~/server/scripts/add-runner.sh Chico7854/<app-repo> <token>
   ```

### Deploy flow

| You do | What happens |
| --- | --- |
| Open a pull request | Tests run on GitHub. Nothing is deployed. |
| Merge or push to `main` | Tests run, then the app deploys to **test**. |
| Push a version tag, e.g. `git tag v1.0.0 && git push origin v1.0.0` | Tests run, then that exact commit deploys to **production**. |

To roll production back, deploy an older tag again by re-running its workflow in the
GitHub Actions tab.

## Not set up yet

- **Backups.** Databases are not backed up. Add backups before storing data you can't lose.
- **Domain.** URLs are random and change on restart until a domain is added.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| `urls.sh` says not ready | `docker compose ps` and `docker compose logs tunnel-prod` |
| `App 'x' is not running in prod` | The app has not been deployed to that environment, or its container stopped. Run `docker ps` and check the app repo's Actions tab. |
| Deploy job stays queued | The runner is offline. Run `sudo ~/actions-runners/<app-repo>/svc.sh status`. |
