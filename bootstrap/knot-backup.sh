#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE="backup"

usage() {
  cat <<'EOF'
Usage: bash bootstrap/knot-backup.sh [--root DIR]

Commits and pushes Knot durable rollback data to the customer-controlled
git remote named "backup".
EOF
}

die() {
  printf 'ERROR %s\n' "$1" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      shift
      [ "$#" -gt 0 ] || die "--root requires a value"
      ROOT="$1"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
  shift
done

ROOT="$(cd "$ROOT" && pwd)"
[ -d "$ROOT/.git" ] || die "backup root is not a git repository: $ROOT"

BACKUP_URL="$(git -C "$ROOT" remote get-url "$REMOTE" 2>/dev/null)" || die "remote 'backup' is missing"
if printf '%s\n' "$BACKUP_URL" | grep -qi 'realraelrr/knot-agent'; then
  die "remote 'backup' points to the scaffold repository: $BACKUP_URL"
fi

BRANCH="$(git -C "$ROOT" symbolic-ref --short HEAD 2>/dev/null)" || die "cannot determine current branch"

stage_if_exists() {
  local path="$1"
  if [ -e "$ROOT/$path" ]; then
    git -C "$ROOT" add -f -- "$path"
  else
    git -C "$ROOT" add -u -- "$path" 2>/dev/null || true
  fi
}

stage_if_exists "AGENTS.md"
stage_if_exists "bootstrap"
stage_if_exists ".skills/knot-setup"
stage_if_exists ".skills/knot-workflow"
stage_if_exists "workspace/knowledge"
stage_if_exists "workspace/admin"

if git -C "$ROOT" diff --cached --quiet; then
  printf 'No backup commit needed; durable rollback data has no staged changes.\n'
  exit 0
fi

DATE="$(date +%Y-%m-%d)"
git -C "$ROOT" commit -m "chore: daily Knot rollback backup $DATE"
git -C "$ROOT" push "$REMOTE" "HEAD:$BRANCH"

COMMIT="$(git -C "$ROOT" rev-parse --short HEAD)"
printf 'Backup pushed: %s %s -> %s/%s\n' "$COMMIT" "$BRANCH" "$REMOTE" "$BRANCH"
