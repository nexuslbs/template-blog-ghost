# Instance A

One of the two stacks in the two-instance, two-theme proof.

* Compose project: `template-blog-ghost-a`
* Published at: `http://localhost:2368`
* Theme (`GHOST_THEME_NAME`): `casper`, declared in `config/themes.lock.json`

Copy `.env.example` to `.env` and drive it with `ENV_FILE`:

```sh
cp instances/a/.env.example instances/a/.env
ENV_FILE=instances/a/.env scripts/up.sh
ENV_FILE=instances/a/.env scripts/bootstrap.sh
ENV_FILE=instances/a/.env scripts/apply.sh
ENV_FILE=instances/a/.env scripts/verify.sh
```

The two instances use different `COMPOSE_PROJECT_NAME` and `GHOST_PORT`, so
they run side by side without clashing. The rendered theme marker is asserted
in the docker run phase (see `instances/b/README.md`); this task is static and
does not start containers.
