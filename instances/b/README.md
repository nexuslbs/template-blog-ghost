# Instance B

The second stack in the two-instance, two-theme proof.

* Compose project: `template-blog-ghost-b`
* Published at: `http://localhost:2369`
* Theme (`GHOST_THEME_NAME`): `journal` (a second theme, not the shipped one)

The shipped `config/themes.lock.json` declares one theme, `casper`. To render a
genuinely different theme in instance B, add the second theme to that lock
(an edit to the manifest, never to the template's own theme files):

```json
{
  "name": "journal",
  "version": "<pinned release>",
  "kind": "official",
  "url": "https://github.com/TryGhost/Journal/archive/refs/tags/<tag>.zip",
  "bytes": 0,
  "sha256": "<sha256 of the zip>",
  "installAs": "journal-<version>",
  "activate": true
}
```

Then run instance B:

```sh
cp instances/b/.env.example instances/b/.env
ENV_FILE=instances/b/.env scripts/up.sh
ENV_FILE=instances/b/.env scripts/bootstrap.sh
ENV_FILE=instances/b/.env scripts/apply.sh
ENV_FILE=instances/b/.env scripts/verify.sh
```

`scripts/apply.sh` verifies the recorded `sha256` and uploads the theme through
the official Admin API. The rendered theme marker is asserted in the docker run
phase; this task is static and starts no container.
