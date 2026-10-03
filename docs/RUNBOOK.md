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
chmod 444 secrets/mysql_root_password.txt  # readable by the unprivileged ghost user
make up
```

`make up` runs `scripts/up.sh`, which starts the stack with the project name
pinned from `.env` and then waits for the `db` and `ghost` healthchecks before
returning. First boot runs Ghost's own DB migrations
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
| `GHOST_MAIL_TRANSPORT` | `Direct` (no external mail) or `SMTP`; this is the only mail knob the shipped compose file reads |
| `MYSQL_ROOT_PASSWORD_FILE` | Host path to the DB password file used as a docker secret |
| `GHOST_ADMIN_*` | First owner + blog title for `bootstrap.sh` (not read by Ghost) |
| `GHOST_THEME_NAME` | Theme to apply; must exist in `config/themes.lock.json` |

To route mail in production set `GHOST_MAIL_TRANSPORT=SMTP` and wire the
`GHOST_MAIL_*` knobs into `docker-compose.yml`. `GHOST_MAIL_TRANSPORT` is the
only one read today (as `mail__transport`); the other knobs in `.env.example`
are placeholders. Add them under the `ghost` service as `mail__options__host`,
`mail__options__port`, `mail__options__auth__user`,
`mail__options__auth__pass` and `mail__from`. This is the only place a config
change touches compose.

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
secret, sent as `Authorization: Ghost <jwt>` (the key id lives in the JWT `kid` header).

## 4. Apply the theme

```sh
make apply
```

Downloads the URL in `config/themes.lock.json`, verifies the recorded sha256,
then `POST /ghost/api/admin/themes/upload/` (multipart field `file`) and
`PUT /ghost/api/admin/themes/<name>/activate/`.

Two official constraints shape this step, both observed against `6.67.0-alpine`:

* **Symlinks are rejected.** An upload containing any symlink entry fails with
  HTTP 415 `SYMLINK_NOT_ALLOWED`. The official Casper `v5.12.5` archive contains
  one (`Casper-5.12.5/CLAUDE.md` -> `AGENTS.md`), so `apply.sh` unpacks it and
  repacks the tree with every link dereferenced (`cp -rL`) before uploading.
* **The bundled default theme cannot be overridden.** Ghost names an uploaded
  theme after the uploaded zip file, and a zip named `casper.zip` is refused with
  HTTP 422 `Please rename your zip, it's not allowed to override the default
  theme.` The lock therefore records `"installAs": "casper-5.12.5"`: the archive
  is uploaded as `casper-5.12.5.zip` and that is the theme that gets activated.
* **Integrations may not list themes.** `GET /ghost/api/admin/themes/` answers
  403 `API tokens do not have permission to access this endpoint` for an
  integration key (it is Owner-only). `verify.sh` reads the active theme from the
  response of the idempotent activate call instead.

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
make backup        # or scripts/backup.sh
```

`scripts/backup.sh` runs these two commands against the project named by
`COMPOSE_PROJECT_NAME` in `.env`, always with `-p` pinned. Never paste a bare
`docker compose` here on a host that exports `COMPOSE_PROJECT_NAME` for another
project: it would target that project instead (on this workstation host the
ambient value is `omni-stack`, i.e. production).

```sh
docker compose -p <project> exec -T db sh -c \
  'exec mysqldump --no-tablespaces -uroot -p"$(cat /run/secrets/ghost_db_secret)" ghost'
docker compose -p <project> exec -T ghost tar czf - -C /var/lib/ghost/content .
```

This stack supplies the password through a file secret, so the script reads it
inside the container with
`-p"$(cat /run/secrets/ghost_db_secret)"` instead of `$MYSQL_ROOT_PASSWORD`.
That is the only deviation from the docs snippet, and it is required by the
`_FILE` secret wiring. `backups/` is gitignored and holds `SHA256SUMS`.

## 7. Restore

Precondition: the compose project exists with its named volumes. `scripts/restore.sh`
brings `db` up and waits for its healthcheck itself, so restore works both right
after `make down` (volumes kept) and after a fresh `make up` over empty volumes.
Pass the backup directory as the `BACKUP` make variable, never as a make goal:

```sh
make restore                          # newest backup
make restore BACKUP=backups/<stamp>   # a specific backup
scripts/restore.sh backups/<stamp>    # the same, without make
```

It ensures `db` is up and healthy, stops Ghost, restores the SQL dump into the
`ghost` database, untars the content tree back into `/var/lib/ghost/content`,
starts Ghost again, and waits for healthy. Ghost runs any needed migrations on
boot.

## 8. Upgrade

1. `make backup` (always).
2. Change the `ghost` image tag in `docker-compose.yml` to the new pinned
   release (never `latest`).
3. `make migrate` (runs `scripts/migrate.sh`, which pins the project with `-p`
   and then recreates ghost); Ghost's `boot.js` ->
   `DatabaseStateManager.makeReady()` applies pending migrations.
4. `make verify`.

There is no official "migration" command to call separately in this image; the
supported route is the container boot. `scripts/migrate.sh` is that boot plus a
read of the latest applied row from the `migrations` table (`name`, `version`,
`currentVersion`).

## 9. Rollback

Rollback is a data restore plus a tag pin, not a command Ghost offers. Run these
steps in this order; each is executable as written:

1. Pin the previous `ghost` tag in `docker-compose.yml` (never `latest`).
2. `make down` (keeps the named volumes).
3. Restore the pre-upgrade dump:
   `make restore BACKUP=backups/<pre-upgrade stamp>`. `scripts/restore.sh` brings
   `db` up and waits for healthy by itself, so this works with the stack down;
   it starts Ghost again at the end.
4. `make up` (idempotent if step 3 already started Ghost) and `make verify`.

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
* **No theme list for integration tokens.** The themes list endpoint is Owner-only;
  an integration key can upload and activate but not enumerate themes.
* **No override of the bundled default theme.** An upload named after the default
  theme is refused; install under a versioned name (`installAs`).
* **No supported in-container Ghost CLI lifecycle.** Docker Hub warns most
  Ghost-CLI commands do not work in the image; this template never depends on
  them, including for migrations and backups.
* **No `_FILE` form for top-level `url`.** Only nested keys support `_FILE`; the
  URL must be a plain env value.
* **No automated downgrade/migrate-down.** Rollback is a dump restore plus a
  tag pin, as in section 9.
* **No built-in TLS.** Put a reverse proxy in front of the published port; Ghost
  itself does not terminate TLS in this image.

## 12. Human handover checklist (production publish is a human step)

The agent prepares the artifact; a named human operator performs the production
publish. Record that name in the deployment ticket and tick every item.

* [ ] **DNS**: an A/AAAA record points the blog host (for example
      `blog.example.com`) at the host that runs the stack.
* [ ] **TLS**: a reverse proxy / TLS terminator sits in front of
      `GHOST_BIND_ADDR:GHOST_PORT`, presents a valid certificate and forwards
      `X-Forwarded-Proto: https`; `GHOST_URL` is the public `https://` URL.
* [ ] **SMTP / mail**: either accept `GHOST_MAIL_TRANSPORT=Direct` (no password
      reset mail) or wire the `GHOST_MAIL_*` values into `docker-compose.yml` as
      `mail__options__*` and `mail__from` (section 2). Send a real test mail.
* [ ] **Real owner**: `GHOST_ADMIN_EMAIL` / `GHOST_ADMIN_PASSWORD` name the real
      owner (not a throwaway), and `make bootstrap` has created that account.
* [ ] **Generated DB secret**: `secrets/mysql_root_password.txt` holds a fresh
      `openssl rand -base64 24` value, is mode 0444 in a 0700 directory, and is
      copied into the operator's secret store. Never commit it.
* [ ] **PRODUCTION PUBLISH (human approval)**: the named human operator reviews
      this checklist, runs `make up` and `make verify` against the production
      `.env`, and performs the DNS cutover. No agent performs this step.
* [ ] **Backups and rollback**: a scheduled `make backup` is in place, and the
      section 9 rollback has been rehearsed against the pre-upgrade dump.
