# template-blog-ghost

The minimum reproducible Ghost (blog) template: the **official** `ghost` image,
the **official** Admin API for every lifecycle action, and a small set of
scripts that orchestrate only official commands.

Pinned images (never `latest`):

| Component | Image | Why this tag |
| --- | --- | --- |
| Ghost | `ghost:6.67.0-alpine` | Pinned current release; `_FILE` env support (>= 6.58.0) |
| Database | `mysql:8.0.44` | The tag the official `TryGhost/ghost-docker` pins |

Prior art: the official [`TryGhost/ghost-docker`](https://github.com/TryGhost/ghost-docker)
repo. This template adapts its compose file, env layout and migration script; it
does not invent mechanisms.

## What it gives you

* `docker-compose.yml` with healthchecks for **both** services, named volumes,
  and the database password supplied through a **file secret** (Ghost's
  `database__connection__password_FILE`, MySQL's `MYSQL_ROOT_PASSWORD_FILE`).
* A non-interactive, browser-free bootstrap of the first owner and an Admin API
  integration, through `/ghost/api/admin/authentication/setup/`,
  `/ghost/api/admin/session/` and `/ghost/api/admin/integrations/`.
* A pinned theme (Casper `v5.12.5`, sha256 verified) uploaded and activated
  through `/ghost/api/admin/themes/`.
* Backup, restore, migrate, verify and teardown scripts plus a runbook.

## Requirements

On the host that runs Docker:

* Docker Engine with Compose v2 (`docker compose`).
* `make` for the Quickstart targets in the `Makefile`.
* `curl`, `jq`, `openssl` (or `node`) for the Admin API scripts.
* `zip` and `unzip` for `scripts/apply.sh` (theme download and symlink repack).
* A reverse proxy / TLS terminator is expected in production; this template
  serves plain HTTP on the published port.

## Quickstart

```sh
cp .env.example .env
# edit .env: GHOST_URL, GHOST_ADMIN_EMAIL, GHOST_ADMIN_PASSWORD, ...
mkdir -p secrets
openssl rand -base64 24 > secrets/mysql_root_password.txt
chmod 444 secrets/mysql_root_password.txt  # readable by the unprivileged ghost user

make up          # start, wait for healthy
make bootstrap   # create owner + Admin API integration (writes runtime/admin-api.json)
make apply       # upload + activate Casper v5.12.5
make verify      # health, db, theme, publish a post, assert public URL is 200
```

`make down` stops the stack and keeps volumes; `make clean` stops it and removes
volumes and the runtime directory.

Or use the scripts directly: `scripts/up.sh`, `scripts/bootstrap.sh`, and so on.

## Deploy

`scripts/deploy.sh` streams this checkout to an SSH-reachable host that has
Docker and drives the same lifecycle scripts there, non-interactively and
idempotently:

```sh
scripts/deploy.sh deploy@blog-host            # sync + up -> bootstrap -> migrate -> verify
scripts/deploy.sh deploy@blog-host --dry-run  # print the exact sequence, touch nothing
scripts/deploy.sh --local                     # run the same sequence on this checkout
```

The target needs only `ssh`, `tar` and `docker`. The script creates `.env` from
`.env.example` and a throwaway DB secret when they are absent; a production
operator provisions `.env` from `production.env.example` first (see
`docs/RUNBOOK.md` section 10). It prints the public `GHOST_URL` at the end.

## Layout

```
docker-compose.yml          pinned stack, healthchecks, secrets
.env.example                every knob, placeholders only
config/
  config.production.json    Ghost config file (no secret; env vars override it)
  themes.lock.json          declared theme(s): Casper v5.12.5 + URL + sha256
scripts/
  lib.sh                    shared helpers (env, compose, JWT signing, health wait)
  up.sh down.sh             lifecycle
  bootstrap.sh              owner + Admin API integration (official APIs)
  apply.sh                  upload + activate the locked theme
  verify.sh                 end-to-end proof including a published post
  backup.sh restore.sh      mysqldump + content tar, per docs.ghost.org
  migrate.sh                migrations via Ghost boot, not the Ghost CLI
  deploy.sh                 ssh/tar deploy wrapper around the scripts above
  logs.sh                   tail logs
docs/RUNBOOK.md             instantiate -> configure -> verify -> backup ->
                            restore -> upgrade -> rollback, sandbox vs prod
Makefile                    thin wrappers over the scripts
evidence/                   raw output captured from a real local run
```

## Security notes

* The real `.env`, `secrets/` and `runtime/` are gitignored. Only
  `.env.example` (placeholders) is committed.
* The database password exists only in `secrets/mysql_root_password.txt` and in
  the container secret mount. It is never written into `.env` or the repo.
* `runtime/admin-api.json` holds the Admin API key secret; it is mode 600 and
  gitignored. The scripts print it redacted.

## Extension model

Ghost has **no plugin system**. There is no server-side extension API for
arbitrary code. Extension is limited to **themes** (Handlebars themes uploaded
through the Admin API) plus the Admin API itself for content and integrations.
Anything that needs custom server logic must run as a separate service that
takes webhooks or polls the Content API. See `docs/RUNBOOK.md`.

The active theme is selected with `GHOST_THEME_NAME` (an entry in
`config/themes.lock.json`). `instances/a/` and `instances/b/` hold EXAMPLE envs
for two stacks with two themes; see `instances/README.md`.

## Licence

The template packaging in this repository is released under the MIT licence
(see `LICENSE`). Ghost core and the official images keep their own upstream
licences; this repository does not redistribute them.
