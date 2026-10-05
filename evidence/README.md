# evidence: raw output from real local runs (2026-10-03)

All files here are raw captured output from the throwaway Compose project
`template-blog-ghost` on this host. Unless a file says otherwise the stack runs
`ghost:6.67.0-alpine` with `mysql:8.0.44`:

* sandbox URL `http://172.18.0.1:2368` (the published port reached through the
  docker bridge gateway from the workstation container)
* throwaway owner, throwaway database password; the Admin API secret and every
  password are redacted
* this host exports `COMPOSE_PROJECT_NAME=omni-stack`; every file shows the
  `template-blog-ghost` resources the scripts pin with `-p`, never the ambient
  project (see `19-migrate.txt` for the pinned image tag)

Two capture passes are mixed, both against the same scratch project. Each row
below states exactly what its file shows.

| file | gate it captures |
| --- | --- |
| `00-docker-ps-before.txt` | `docker ps` before host hygiene |
| `01-docker-ps-after-hygiene.txt` | `docker ps` after stopping every non-`omni-stack` container |
| `10-up.txt` | COLD `scripts/up.sh` on empty volumes: quotes `Network/Volume/Container ... Creating` then `... Created`, both healthchecks, `ghost:6.67.0-alpine` |
| `11-site-health.txt` | `curl -i /ghost/api/admin/site/` and the setup-status endpoint |
| `12-bootstrap.txt` | the 4-step non-interactive bootstrap, HTTP codes, keys redacted |
| `13-apply-theme.txt` | Casper v5.12.5 upload (`HTTP 200`) + activate (`HTTP 200`) |
| `13a-theme-upload-error.txt` | earlier `Invalid token` (the `<id>:` header mistake) |
| `13c-theme-upload-415.txt` | `SYMLINK_NOT_ALLOWED` for the upstream Casper zip |
| `13d-theme-name-test.txt` | `HTTP 422`, the bundled default theme cannot be overridden |
| `13e-theme-get-test.txt` | `GET /themes/` is 403 for an integration token |
| `14-verify.txt` | site, db, setup, active theme, publish, public URL 200 |
| `15-ps.txt` | `scripts/ps.sh`, both services healthy |
| `16-logs-ghost.txt` | `scripts/logs.sh` ghost (last 50 lines) |
| `17-stats.txt` | `docker stats --no-stream` for both containers |
| `18-backup.txt` | `scripts/backup.sh` (mysqldump + content tar) |
| `19-migrate.txt` | REAL upgrade `ghost:6.65.0-alpine` -> `ghost:6.67.0-alpine`: pinned tag before/after, `migrations` count 349 -> 351, latest row 6.65 -> 6.67, and Ghost boot lines `Database state requires migration.` / `Running migrations.` / `Database is in a ready state.` |
| `19a-db-version-probe.txt` | probe showing no `databaseVersion` settings key |
| `19b-migrations-table.txt` | the `migrations` table is the schema-version source |
| `20-restore.txt` | REAL destroy-plus-empty-volume round trip: `down --volumes` (containers + volumes + network removed, `docker ps -a` / `docker volume ls` quoted) -> fresh `up` on empty volumes -> marker post 404 -> `scripts/restore.sh` -> marker post 200. The second section is the documented ROLLBACK `down` (keeps volumes) -> `restore` -> `up`, marker post 200 |
| `21-teardown.txt` | `git ls-files`, `down --volumes`, and `docker ps` proving the project is gone |

## WAVE 3 live-gate pass (2026-10-05, thread 4080)

Two instances (`template-blog-ghost-a` port 2368, `template-blog-ghost-b` port
2369) under the default project `template-blog-ghost` (port 2370). Only the
gitignored `instances/*/.env` differ per instance; no template file is edited to
render a theme.

| file | gate it captures |
| --- | --- |
| `d6-two-theme-live.txt` | TWO-THEME: same checkout, A=casper (`/assets/built/casper.js`) and B=source (`/assets/built/source.js`), each booted, bootstrapped, themed, verified; separate `RUNTIME_DIR` files quoted |
| `d4-backup-restore-live.txt` | BACKUP/RESTORE: pre-backup post HTTP 200 -> `backup.sh` -> `down --volumes` (volumes gone) -> fresh `up` -> post HTTP 404 -> `restore.sh` -> post HTTP 200 -> `verify.sh` OK |
| `d5-upgrade-live.txt` | MIGRATE/UPGRADE: real tag bump `ghost:6.65.0-alpine` -> `ghost:6.67.0-alpine`, `migrations` 349 -> 351, boot log `Database state requires migration.` / `Running migrations.`, post 200, then rollback = previous tag + pre-upgrade dump, post 200 again |
| `d7-plugin-status-live.txt` | PLUGIN status: Ghost has NO plugin system; live container has no `plugins` dir, only `themes`; first-party docs corroborate themes + integrations only |
| `d8-deploy-live.txt` | DEPLOY: `--help`, remote `--dry-run` (ssh/tar + compose sequence), real `--local` run ending `deploy: OK`; remote leg is contract + dry-run only |
| `live-gate-teardown.txt` | teardown: every project `down --volumes`; `docker ps` lists only `omni-stack-*`; no ghost volumes left |


## Findings proven by this run

* The published post URL answers HTTP 200 through the public route.
* A real image bump `ghost:6.65.0-alpine` -> `ghost:6.67.0-alpine` is an
  upgrade: Ghost's boot migrator adds 2 rows to the `migrations` table
  (349 -> 351), advances the latest `currentVersion` from 6.65 to 6.67, and logs
  `Database state requires migration.`, `Running migrations.` and
  `Database is in a ready state.` The published post still answers 200.
* `down --volumes` destroys both named volumes and the network; a fresh `up` on
  empty volumes serves the old post URL as HTTP 404, and `scripts/restore.sh`
  brings it back to HTTP 200.
* `scripts/restore.sh` brings `db` up and waits for its healthcheck before it
  writes, so the documented rollback order `down` (keep volumes) -> `restore`
  -> `up` completes (it previously failed with `service "db" is not running`).
* The upstream Casper `v5.12.5` zip cannot be uploaded as is: it contains a
  symlink entry (`Casper-5.12.5/CLAUDE.md`), and Ghost 6.67 refuses it with
  HTTP 415 `SYMLINK_NOT_ALLOWED`. `apply.sh` repacks with links dereferenced.
* A zip named `casper.zip` is refused with HTTP 422 because it would override
  the bundled default theme; the lock installs it as `casper-5.12.5`.
* Ghost 6.67 accepts `Authorization: Ghost <jwt>`; the key id belongs in the JWT
  `kid` header, and the integration `secret` is returned as
  `<id>:<hex-secret>`, so the JWT is signed with the part after the colon.
* Theme list (`GET /themes/`) is Owner-only and answers 403 for integration
  tokens; upload and activate work, so `verify.sh` reads the active theme from
  the activate response.
* The database password must be readable by the unprivileged `node` user in the
  Ghost container; the compose file secret preserves the host file mode, so the
  file is `0444` inside a `0700` directory.

## Not covered here

* No external mail was sent (`GHOST_MAIL_TRANSPORT=Direct`).
* TLS and a reverse proxy are out of scope for the sandbox run.
