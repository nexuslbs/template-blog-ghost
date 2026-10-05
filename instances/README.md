# instances: two-instance, two-theme proof

This directory holds EXAMPLE env files for running two independent Ghost
stacks from the same checkout, each with its own Compose project, its own
runtime directory and its own theme. They document the theme override knob.

The override knob is `GHOST_THEME_NAME`. It selects an entry in
`config/themes.lock.json`; `scripts/apply.sh` and `scripts/verify.sh` read it.
The shipped lock declares two official themes, `casper` and `source`.

Each instance also sets `RUNTIME_DIR`, so the Admin API credentials written by
`scripts/bootstrap.sh` do not clobber each other when both instances run.

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
`.env.example` templates are committed. `instances/*/runtime/` is gitignored by
the `runtime/` rule. The generated `.env` and runtime trees are removed after
the audit run.
