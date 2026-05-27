#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: bash tests/integration.sh [--root DIR]

Runs Knot helper smoke tests against temporary workspaces.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      shift
      if [ "$#" -eq 0 ]; then
        printf 'MISS --root requires a value\n'
        exit 1
      fi
      ROOT="$1"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'MISS unknown argument: %s\n' "$1"
      exit 1
      ;;
  esac
  shift
done

ROOT="$(cd "$ROOT" && pwd)" || {
  printf 'MISS root directory does not exist: %s\n' "$ROOT"
  exit 1
}

# shellcheck source=tests/lib/integration-common.sh
. "$ROOT/tests/lib/integration-common.sh"

# Suites are orchestrated in this order and are not standalone entrypoints.
for suite in workspace governance knowledge planning_lifecycle collaborator_profile profile_lifecycle delivery operations installer docs source_contracts; do
  # shellcheck source=/dev/null
  . "$ROOT/tests/integration/$suite.sh"
done

if [ "$FAILURES" -gt 0 ]; then
  exit 1
fi
