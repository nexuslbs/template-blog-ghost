# RUNBOOK: template-blog-ghost

Everything here orchestrates **official** mechanisms: the official
`ghost:6.67.0-alpine` image, `mysql:8.0.44`, the `__`-nested environment
variables, the Admin API, and the backup commands from
`docs.ghost.org/faq/manual-backup`. Where no official route exists, this
document says so instead of inventing one.

## 0. Design facts this template relies on

* Ghost reads `/var/lib/ghost/config.production.json`; every value is
  overridable with `__`-nested env vars (for example
  `database__connection__host=db`).
* Ghost >= 6.58.0 supports the `_FILE` suffix for nested keys, so
  `database__connection__password_FILE=/run/secrets/ghost_db_secret` works.
  Top-level `url` has **no** `_FILE` form.
* Setting both `X__y` and `X__y_FILE` makes Ghost refuse to start. This template
  sets only the `_FILE` form for the password and never the inline key.
* Ghost has **no plugin system**. There is no supported server-side extension
  point. Extensibility is themes only (Handlebars themes uploaded via the Admin
  API); content, members and integrations go through the official APIs. Custom
  server logic must be a separate service using webhooks or the Content API.
* The in-image Ghost CLI is unreliable. Docker Hub explicitly warns that most
  Ghost-CLI commands do not work in the container. Do not build lifecycle steps
  on `ghost <command>`.

## 1. Instantiate

```sh
git clone https://github.com/nexuslbs/template-blog-ghost.git
cd template-blog-ghost
cp .env.example .env
# edit .env (see the table below)
mkdir -p secrets
openssl rand -base64 24 > secrets/mysql_root_password.txt
chmod 600 secrets/mysql_root_password.txt
make up
```

`make up` runs `docker compose up -d`, then waits for the `db` and `ghost`
healthchecks before returning. First boot runs Ghost's own DB migrations
(`boot.js` -> `DatabaseStateManager.makeReady()`), which is why the ghost
healthcheck has a long start period.

## 2. Configure

All configuration is environment-only; the committed
`config/config.production.json` carries no secret and is overridden by the
nested env vars in `docker-compose.yml`.

| Knob (`.env`) | Effect |
| --- | --- |
| `COMPOSE_PROJECT_NAME` | Container/volume/network name prefix; one project per stack |
| `GHOST_URL` | Public URL Ghost serves and uses for absolute links (no trailing slash) |
| `GHOST_BIND_ADDR` / `GHOST_PORT` | Where the container port is published on the host |
| `GHOST_MAIL_TRANSPORT` | `Direct` (no external mail) or `SMTP`; fill the SMTP knobs for production |
| `MYSQL_ROOT_PASSWORD_FILE` | Host path to the DB password file used as a docker secret |
| `GHOST_ADMIN_*` | First owner + blog title for `bootstrap.sh` (not read by Ghost) |
| `GHOST_THEME_NAME` | Theme to apply; must exist in `config/themes.lock.json` |

To route mail in production set `GHOST_MAIL_TRANSPORT=SMTP` and the
`GHOST_MAIL_*` knobs. They map to `mail__transport`, `mail__options__host`,
`mail__options__port`, `mail__options__auth__user`,
`mail__options__auth__pass` and `mail__from`. Extend `docker-compose.yml`
accordingly; this is the only place a config change touches compose.

## 3. Bootstrap (non-interactive, no browser)

```sh
make bootstrap
```

Order, all through the official Admin API:

1. `GET  $GHOST_URL/ghost/api/admin/site/` (health).
2. `POST $GHOST_URL/ghost/api/admin/authentication/setup/` with
   `{"setup":[{name,email,password,blogTitle}]}`. Unauthenticated and only
   accepted before setup; returns 201.
3. `POST $GHOST_URL/ghost/api/admin/session/` with the `Origin: $GHOST_URL`
   header; returns 201 and the `ghost-admin-api-session` cookie. A fresh
   owner's first login skips device verification.
4. `POST $GHOST_URL/ghost/api/admin/integrations/?include=api_keys` with that
   cookie; returns an integration with a `content` and an `admin` API key.

The Admin API key id/secret are written to `runtime/admin-api.json` (mode 600,
gitignored). Later requests sign a JWT: header
`{"alg":"HS256","typ":"JWT","kid":"<id>"}`, payload
`{"iat":now,"exp":now+300,"aud":"/admin/"}`, HMAC-SHA256 over the **hex-decoded**
secret, sent as `Authorization: Ghost <id>:<jwt>`.

## 4. Apply the theme

```sh
make apply
```

Downloads the URL in `config/themes.lock.json`, verifies the recorded sha256,
then `POST /ghost/api/admin/themes/upload/` (multipart field `file`) and
`PUT /ghost/api/admin/themes/<name>/activate/`.

## 5. Verify

```sh
make verify
```

Checks the site endpoint, the database, the setup state, the active theme, then
publishes a post with `POST /ghost/api/admin/posts/?source=html` and asserts the
returned `posts[0].url` answers HTTP 200.

## 6. Backup

```sh
make backup
```

Per `docs.ghost.org/faq/manual-backup`, into `backups/<UTC timestamp>/`:

```sh
docker compose exec -T db sh -c \
  'exec mysqldump --no-tablespaces -uroot -p"$MYSQL_ROOT_PASSWORD" ghost'
docker compose exec -T ghost tar czf - -C /var/lib/ghost/content .
```

This stack supplies the password through a file secret, so the script reads it
inside the container with
`-p"$(cat /run/secrets/ghost_db_secret)"` instead of `$MYSQL_ROOT_PASSWORD`.
That is the only deviation from the docs snippet, and it is required by the
`_FILE` secret wiring. `backups/` is gitignored and holds `SHA256SUMS`.

## 7. Restore

```sh
make restore                 # newest backup
scripts/restore.sh backups/20261003T210000Z
```

Stops Ghost, restores the SQL dump into the `ghost` database, untars the content
tree back into `/var/lib/ghost/content`, restarts Ghost, and waits for healthy.
Ghost runs any needed migrations on boot.

## 8. Upgrade

1. `make backup` (always).
2. Change the `ghost` image tag in `docker-compose.yml` to the new pinned
   release (never `latest`).
3. `make migrate` (`docker compose up -d --force-recreate ghost`); Ghost's
   `boot.js` -> `DatabaseStateManager.makeReady()` applies pending migrations.
4. `make verify`.

There is no official "migration" command to call separately in this image; the
supported route is the container boot. `scripts/migrate.sh` is that boot plus a
schema-version read from the `settings` table (`databaseVersion`).

## 9. Rollback

Rollback is a data restore plus a tag pin, not a command Ghost offers:

1. Pin the previous `ghost` tag in `docker-compose.yml`.
2. `make down` (keep volumes).
3. Restore the pre-upgrade dump: `make restore backups/<pre-upgrade stamp>`.
4. `make up` and `make verify`.

Because the migration only moves forward, restoring the HTTP service without the
matching database state is not supported by any official route. Keep the
pre-upgrade dump; it is the only rollback path.

## 10. Sandbox vs production: config-only diff

The compose file, images, volumes and scripts are **identical**. Only `.env`
values differ:

| Knob | Sandbox | Production |
| --- | --- | --- |
| `GHOST_URL` | `http://<host>:2368` | `https://blog.example.com` |
| `GHOST_BIND_ADDR` | `127.0.0.1` (or `0.0.0.0` for a reachable sandbox) | `127.0.0.1` behind a TLS reverse proxy |
| `GHOST_PORT` | `2368` | often `2368` internal, proxy terminates 443 |
| DB password file | throwaway value | generated secret, injected by the platform |
| `GHOST_MAIL_TRANSPORT` | `Direct` | `SMTP` + `GHOST_MAIL_*` |
| `GHOST_ADMIN_*` | throwaway owner | real owner, set once |
| `COMPOSE_PROJECT_NAME` | throwaway project | production project |

No compose edit is needed to promote: copy `.env`, generate the secret, point DNS
and TLS at the published port.

## 11. No official route (explicit gaps)

* **No plugin system.** Ghost does not support server-side plugins. There is no
  official hook to run custom Node code inside the Ghost process. Themes and the
  Admin/Content APIs are the only extension surfaces.
* **No supported in-container Ghost CLI lifecycle.** Docker Hub warns most
  Ghost-CLI commands do not work in the image; this template never depends on
  them, including for migrations and backups.
* **No `_FILE` form for top-level `url`.** Only nested keys support `_FILE`; the
  URL must be a plain env value.
* **No automated downgrade/migrate-down.** Rollback is a dump restore plus a
  tag pin, as in section 9.
* **No built-in TLS.** Put a reverse proxy in front of the published port; Ghost
  itself does not terminate TLS in this image.
