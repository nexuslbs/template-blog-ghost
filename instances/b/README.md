# Instance B

The second stack in the two-instance, two-theme proof.

* Compose project: `template-blog-ghost-b`
* Published at: `http://localhost:2369`
* Theme (`GHOST_THEME_NAME`): `source` (a second official theme, not `casper`)
* Runtime dir: `instances/b/runtime` (kept apart from instance A's creds)

The shipped `config/themes.lock.json` declares two official themes: `casper`
(instance A) and `source` (instance B). `scripts/apply.sh` downloads the pinned
archive, verifies the recorded `sha256`, uploads it through the official Admin
API and activates it. No theme file and no script is edited per instance; the
only per-instance input is the `.env` file.

Run instance B:

```sh
cp instances/b/.env.example instances/b/.env
ENV_FILE=instances/b/.env scripts/up.sh
ENV_FILE=instances/b/.env scripts/bootstrap.sh
ENV_FILE=instances/b/.env scripts/apply.sh
ENV_FILE=instances/b/.env scripts/verify.sh
```

The rendered theme is asserted by the served page: Casper serves
`/assets/built/casper.js` and Source serves `/assets/built/source.js`.
