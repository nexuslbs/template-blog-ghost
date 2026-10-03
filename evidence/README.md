# evidence: raw output from a real local run (2026-10-03)

All files here are raw captured output from ONE throwaway Compose project,
`template-blog-ghost`, on this host:

* `ghost:6.67.0-alpine`, `mysql:8.0.44`
* sandbox URL `http://172.18.0.1:2368` (the published port reached through the
  docker bridge gateway from the workstation container)
* throwaway owner, throwaway database password; the Admin API secret and every
  password are redacted

| file | gate it captures |
| --- | --- |
| `00-docker-ps-before.txt` | `docker ps` before host hygiene |
| `01-docker-ps-after-hygiene.txt` | `docker ps` after stopping every non-`omni-stack` container |
| `10-up.txt` | `scripts/up.sh` = `docker compose up -d` + both healthchecks |
| `11-site-health.txt` | `curl -i /ghost/api/admin/site/` and the setup-status endpoint |
| `12-bootstrap.txt` | the 4-step non-interactive bootstrap, HTTP codes, keys redacted |
| `13-apply-theme.txt` | Casper v5.12.5 upload (`HTTP 200`) + activate (`HTTP 200`) |
| `13a-theme-upload-error.txt` | earlier `Invalid token` (the `<id>:` header mistake) |
| `13c-theme-upload-415.txt` | `SYMLINK_NOT_ALLOWED` for the upstream Casper zip |
| `13d-theme-name-test.txt` | `HTTP 422`, the bundled default theme cannot be overridden |
| `13e-theme-get-test.txt` | `GET /themes/` is 403 for an integration token |
| `14-verify.txt` | site, db, setup, active theme, publish, public URL 200 |
| `15-ps.txt` | `docker compose ps`, both services healthy |
| `16-logs-ghost.txt` | `docker compose logs --tail=50 ghost` |
| `17-stats.txt` | `docker stats --no-stream` for both containers |
| `18-backup.txt` | `scripts/backup.sh` (mysqldump + content tar) |
| `19-migrate.txt` | `scripts/migrate.sh` and the latest `migrations` row |
| `19a-db-version-probe.txt` | probe showing no `databaseVersion` settings key |
| `19b-migrations-table.txt` | the `migrations` table is the schema-version source |
| `20-restore.txt` | `scripts/restore.sh` round trip, both services healthy again |
| `21-teardown.txt` | `git ls-files`, `down --volumes`, and `docker ps` proving the project is gone |

## Findings proven by this run

* The published post URL answers HTTP 200 through the public route.
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
