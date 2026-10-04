# instances: two-instance, two-theme proof

This directory holds EXAMPLE env files for running two independent Ghost
stacks from the same checkout, each with its own Compose project and its own
theme. They document the theme override knob and are the scaffolding for the
A/B proof.

The override knob is `GHOST_THEME_NAME`. It selects an entry in
`config/themes.lock.json`; `scripts/apply.sh` and `scripts/verify.sh` read it.

`instances/a/` and `instances/b/` are not used by the default `make` targets.
Run an instance by pointing the `ENV_FILE` variable at its env file:

```sh
cp instances/a/.env.example instances/a/.env
ENV_FILE=instances/a/.env scripts/up.sh
ENV_FILE=instances/a/.env scripts/bootstrap.sh
ENV_FILE=instances/a/.env scripts/apply.sh
ENV_FILE=instances/a/.env scripts/verify.sh
```

`.env` files under `instances/` are gitignored by the `.env` rule; only the
`.env.example` templates are committed.

The shipped `config/themes.lock.json` declares one theme (`casper`). To make
instance B render a genuinely different theme, add a second pinned theme to
that lock (or to a project-owned lock) and set `GHOST_THEME_NAME` to its name.
Doing so edits the manifest, never the template's own theme files. See
`instances/b/README.md`.
