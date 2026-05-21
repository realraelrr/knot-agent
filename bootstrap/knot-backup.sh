#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=bootstrap/lib.sh
. "$SCRIPT_DIR/lib.sh"
REMOTE="backup"

usage() {
  cat <<'EOF'
Usage: bash bootstrap/knot-backup.sh [--root DIR]

Commits and pushes Knot durable rollback data to the customer-controlled
git remote named "backup".
EOF
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
for unsafe_remote in origin scaffold; do
  unsafe_url="$(git -C "$ROOT" remote get-url "$unsafe_remote" 2>/dev/null || true)"
  if [ -n "$unsafe_url" ] && [ "$BACKUP_URL" = "$unsafe_url" ]; then
    die "remote 'backup' matches '$unsafe_remote'; configure a customer-controlled backup remote"
  fi
done

BRANCH="$(git -C "$ROOT" symbolic-ref --short HEAD 2>/dev/null)" || die "cannot determine current branch"

stage_if_exists() {
  local path="$1"
  if [ -e "$ROOT/$path" ]; then
    git -C "$ROOT" add -f -- "$path"
  else
    git -C "$ROOT" add -u -- "$path" 2>/dev/null || true
  fi
}

stage_pathspec_update() {
  local pathspec="$1"
  git -C "$ROOT" add -u -- "$pathspec" 2>/dev/null || true
}

stage_found_files() {
  local base="$1"
  shift

  [ -d "$ROOT/$base" ] || return 0
  while IFS= read -r -d '' file; do
    git -C "$ROOT" add -f -- "${file#"$ROOT/"}"
  done < <(find "$ROOT/$base" "$@" -print0)
}

stage_workspace_metadata() {
  stage_pathspec_update "workspace/users/*/profile.tsv"
  stage_pathspec_update "workspace/users/*/identities.tsv"
  stage_pathspec_update "workspace/groups/*/profile.tsv"
  stage_pathspec_update "workspace/groups/*/members.tsv"
  stage_pathspec_update "workspace/conversations/*/*/metadata.tsv"

  stage_found_files "workspace/users" -mindepth 2 -maxdepth 2 \( -name profile.tsv -o -name identities.tsv \)
  stage_found_files "workspace/groups" -mindepth 2 -maxdepth 2 \( -name profile.tsv -o -name members.tsv \)
  stage_found_files "workspace/conversations" -mindepth 3 -maxdepth 3 -name metadata.tsv
}

stage_if_exists "AGENTS.md"
stage_if_exists "bootstrap"
stage_if_exists ".skills/knot-setup"
stage_if_exists ".skills/knot-workflow"
stage_if_exists "workspace/knowledge"
stage_if_exists "workspace/admin"
stage_workspace_metadata

if git -C "$ROOT" diff --cached --quiet; then
  printf 'No backup commit needed; durable rollback data has no staged changes.\n'
  exit 0
fi

DATE="$(date +%Y-%m-%d)"
git -C "$ROOT" commit -m "chore: daily Knot rollback backup $DATE"
git -C "$ROOT" push "$REMOTE" "HEAD:$BRANCH"

COMMIT="$(git -C "$ROOT" rev-parse --short HEAD)"
printf 'Backup pushed: %s %s -> %s/%s\n' "$COMMIT" "$BRANCH" "$REMOTE" "$BRANCH"
