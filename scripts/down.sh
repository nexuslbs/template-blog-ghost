#!/usr/bin/env bash
# Stop the stack. Named volumes (database, content) are KEPT unless --volumes.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

require_cmd docker
load_env

remove_volumes=0
for arg in "$@"; do
  case "$arg" in
    -v|--volumes) remove_volumes=1 ;;
    *) die "unknown argument: $arg (usage: down.sh [--volumes])" ;;
  esac
done

if [ "$remove_volumes" -eq 1 ]; then
  log "down --volumes (deletes db-data and ghost-content)"
  compose down --volumes
else
  log "down (keeps named volumes)"
  compose down
fi

compose ps
log "down: OK"
