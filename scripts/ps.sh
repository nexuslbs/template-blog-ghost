#!/usr/bin/env bash
# Show this stack's service state, pinned to its own compose project.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

require_cmd docker
load_env
compose ps
