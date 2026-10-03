# Thin wrappers over scripts/. Every target is non-interactive.
SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help up down clean bootstrap apply verify backup restore migrate logs ps

help: ## list targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  %-12s %s\n", $$1, $$2}'

up: ## start the stack and wait for both services to be healthy
	scripts/up.sh

down: ## stop the stack, keep named volumes
	scripts/down.sh

clean: ## stop the stack and delete volumes + runtime
	scripts/down.sh --volumes
	rm -rf runtime

bootstrap: ## create the owner and an Admin API integration
	scripts/bootstrap.sh

apply: ## upload + activate the locked theme
	scripts/apply.sh

verify: ## health, db, theme, publish a post, assert public 200
	scripts/verify.sh

backup: ## dump the database and the content tree into backups/
	scripts/backup.sh

restore: ## restore a backup: make restore [BACKUP=backups/<stamp>]
	scripts/restore.sh "$(if $(BACKUP),$(BACKUP),newest)"

migrate: ## recreate ghost so boot.js applies pending migrations
	scripts/migrate.sh

logs: ## tail logs: make logs [TAIL=100] [SERVICE=ghost]
	TAIL="$(if $(TAIL),$(TAIL),100)" scripts/logs.sh $(SERVICE)

ps: ## show service state (pinned to this stack's project)
	scripts/ps.sh
