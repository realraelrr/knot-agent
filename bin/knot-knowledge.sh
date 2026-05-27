#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="${KNOT_ROOT:-$DEFAULT_ROOT}"
# shellcheck source=lib/knot/core.sh
. "$DEFAULT_ROOT/lib/knot/core.sh"

COMMAND="${1:-}"
[ "$#" -eq 0 ] || shift

REPO_URL="${KNOT_KNOWLEDGE_REPO_URL:-}"
MIRROR="${KNOT_KNOWLEDGE_LOCAL_MIRROR:-}"
APPROVED_REF="${KNOT_KNOWLEDGE_APPROVED_REF:-main}"
SOURCE=""
TITLE="proposal"
PLATFORM="${KNOT_PLATFORM:-}"
USER_ID="${KNOT_PLATFORM_USER_ID:-}"
IDENTITY_KEY="${KNOT_IDENTITY_KEY:-}"
USER_SLUG="${KNOT_ACTOR_USER:-}"

usage() {
  cat <<'EOF'
Usage: bash bin/knot-knowledge.sh COMMAND [options]

Commands:
  status
  sync-approved
  propose --source DIR [--title NAME]

Options:
  --root DIR
  --repo-url URL
  --mirror DIR
  --approved-ref REF
  --source DIR
  --title NAME
  --platform NAME
  --user-id ID
  --identity-key KEY
  --actor-user SLUG
EOF
}

slugify_title() {
  printf '%s' "$1" |
    tr '[:upper:]' '[:lower:]' |
    sed -e 's/[^a-z0-9._-]/-/g' -e 's/-\{2,\}/-/g' -e 's/^-//' -e 's/-$//' |
    cut -c1-60
}

actor_role() {
  permissions_actor_role_or_default "$ROOT" "$PLATFORM" "$USER_ID" "$IDENTITY_KEY" "$USER_SLUG" member
}

require_admin() {
  local role="$1"
  [ "$role" = "admin" ] || die "durable knowledge approval requires explicit admin role"
}

require_mirror() {
  [ -n "$MIRROR" ] || MIRROR="$ROOT/workspace/knowledge/vault"
  if [ -L "$MIRROR" ]; then
    die "knowledge mirror must not be a symlink: $MIRROR"
  fi
}

validate_approved_ref() {
  if [ "$APPROVED_REF" = "main" ]; then
    return 0
  fi
  printf '%s' "$APPROVED_REF" | grep -Eq '^[0-9a-f]{40}$' ||
    die "approved knowledge ref must be main or a pinned 40-character commit SHA"
}

ensure_clean_git_worktree() {
  local dir="$1"
  if [ -n "$(git -C "$dir" status --porcelain)" ]; then
    die "knowledge mirror has uncommitted changes"
  fi
}

copy_proposal_files() {
  local source_dir="$1"
  local dest_dir="$2"
  local rel

  mkdir -p "$dest_dir/files"
  while IFS= read -r -d '' file; do
    rel="${file#"$source_dir/"}"
    mkdir -p "$dest_dir/files/$(dirname "$rel")"
    cp "$file" "$dest_dir/files/$rel"
  done < <(find "$source_dir" -type f ! -path '*/.git/*' -print0)
  knot_manifest_write_dir "$dest_dir/files" "$dest_dir/manifest.tsv"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      shift; [ "$#" -gt 0 ] || die "--root requires a value"; ROOT="$1" ;;
    --repo-url)
      shift; [ "$#" -gt 0 ] || die "--repo-url requires a value"; REPO_URL="$1" ;;
    --mirror)
      shift; [ "$#" -gt 0 ] || die "--mirror requires a value"; MIRROR="$1" ;;
    --approved-ref)
      shift; [ "$#" -gt 0 ] || die "--approved-ref requires a value"; APPROVED_REF="$1" ;;
    --source)
      shift; [ "$#" -gt 0 ] || die "--source requires a value"; SOURCE="$1" ;;
    --title)
      shift; [ "$#" -gt 0 ] || die "--title requires a value"; TITLE="$1" ;;
    --platform)
      shift; [ "$#" -gt 0 ] || die "--platform requires a value"; PLATFORM="$1" ;;
    --user-id)
      shift; [ "$#" -gt 0 ] || die "--user-id requires a value"; USER_ID="$1" ;;
    --identity-key)
      shift; [ "$#" -gt 0 ] || die "--identity-key requires a value"; IDENTITY_KEY="$1" ;;
    --actor-user|--user-slug)
      shift; [ "$#" -gt 0 ] || die "--actor-user requires a value"; USER_SLUG="$1" ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      die "unknown argument: $1" ;;
  esac
  shift
done

[ -n "$COMMAND" ] || die "command is required"
ROOT="$(cd "$ROOT" && pwd -P)"
require_mirror
ROLE="$(actor_role)"

case "$COMMAND" in
  status)
    printf 'role=%s\n' "$ROLE"
    printf 'mirror=%s\n' "$MIRROR"
    printf 'approved_ref=%s\n' "$APPROVED_REF"
    if [ -d "$MIRROR/.git" ]; then
      printf 'branch=%s\n' "$(git -C "$MIRROR" branch --show-current)"
    fi
    ;;
  sync-approved)
    require_admin "$ROLE"
    [ -n "$REPO_URL" ] || die "--repo-url or KNOT_KNOWLEDGE_REPO_URL is required"
    validate_approved_ref
    if [ -d "$MIRROR/.git" ]; then
      ensure_clean_git_worktree "$MIRROR"
      [ "$(git -C "$MIRROR" remote get-url origin)" = "$REPO_URL" ] ||
        die "knowledge mirror origin does not match configured repository URL"
    else
      mkdir -p "$(dirname "$MIRROR")"
      git clone --no-checkout "$REPO_URL" "$MIRROR" >/dev/null
    fi
    git -C "$MIRROR" fetch origin main >/dev/null
    if [ "$APPROVED_REF" = "main" ]; then
      git -C "$MIRROR" checkout -B main "origin/main" >/dev/null 2>&1
      git -C "$MIRROR" reset --hard "origin/main" >/dev/null
    else
      git -C "$MIRROR" cat-file -e "$APPROVED_REF^{commit}" >/dev/null 2>&1 &&
        git -C "$MIRROR" merge-base --is-ancestor "$APPROVED_REF" "origin/main" ||
        die "pinned approved commit is not reachable from origin/main"
      git -C "$MIRROR" checkout --detach "$APPROVED_REF" >/dev/null 2>&1
      git -C "$MIRROR" reset --hard "$APPROVED_REF" >/dev/null
    fi
    printf 'synced: %s %s\n' "$MIRROR" "$APPROVED_REF"
    ;;
  propose)
    [ -n "$USER_SLUG" ] || die "--actor-user or KNOT_ACTOR_USER is required"
    validate_slug "--actor-user" "$USER_SLUG"
    [ -n "$SOURCE" ] || die "--source is required"
    SOURCE="$(absolute_path "$SOURCE")" || die "cannot resolve proposal source"
    [ -d "$SOURCE" ] || die "proposal source is not a directory: $SOURCE"
    [ ! -L "$SOURCE" ] || die "proposal source must not be a symlink: $SOURCE"
    if find "$SOURCE" -type l -print -quit | grep -q .; then
      die "proposal source must not contain symlinks"
    fi
    actor_workspace="$(absolute_path "$(knot_scope_user_workspace "$ROOT" "$USER_SLUG")")" ||
      die "cannot resolve actor workspace"
    mirror_abs="$(absolute_path "$MIRROR" 2>/dev/null || true)"
    if [ "$ROLE" != "admin" ]; then
      [ -z "${GH_TOKEN:-}" ] && [ -z "${GITHUB_TOKEN:-}" ] ||
        die "member proposal refused because GitHub token is visible in the environment"
      path_is_under "$SOURCE" "$actor_workspace" ||
        die "member knowledge proposals must come from the actor workspace"
      if [ -n "$mirror_abs" ] && { [ "$SOURCE" = "$mirror_abs" ] || path_is_under "$SOURCE" "$mirror_abs"; }; then
        die "member knowledge proposals must not use the approved mirror as source"
      fi
    fi
    slug="$(slugify_title "$TITLE")"
    [ -n "$slug" ] || slug="proposal"
    ensure_dir_no_symlink "$ROOT/workspace" "workspace root"
    ensure_dir_no_symlink "$ROOT/workspace/users" "users root"
    ensure_dir_no_symlink "$actor_workspace" "actor workspace"
    ensure_dir_no_symlink "$actor_workspace/.knot" "actor knowledge proposal context"
    ensure_dir_no_symlink "$actor_workspace/.knot/knowledge-proposals" "actor knowledge proposal root"
    proposal_dir="$actor_workspace/.knot/knowledge-proposals/$(date -u '+%Y%m%dT%H%M%SZ')-$slug"
    mkdir -p "$proposal_dir"
    copy_proposal_files "$SOURCE" "$proposal_dir"
    {
      printf 'title\t%s\n' "$TITLE"
      printf 'actor\t%s\n' "$USER_SLUG"
      printf 'role\t%s\n' "$ROLE"
      printf 'source\t%s\n' "${SOURCE#"$ROOT/"}"
    } > "$proposal_dir/proposal.tsv"
    printf 'proposal: %s\n' "$proposal_dir"
    ;;
  *)
    die "unknown command: $COMMAND"
    ;;
esac
