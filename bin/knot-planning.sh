#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="${KNOT_ROOT:-$DEFAULT_ROOT}"
# shellcheck source=lib/knot/core.sh
. "$DEFAULT_ROOT/lib/knot/core.sh"

COMMAND="${1:-}"
[ "$#" -eq 0 ] || shift

SCOPE="${KNOT_SCOPE:-root}"
USER_SLUG="${KNOT_ACTOR_USER:-}"
GROUP_SLUG="${KNOT_GROUP_SLUG:-${KNOT_SOURCE_GROUP:-}}"
TASK_ID="${PLAN_ID:-}"
NOW="$(timestamp_utc)"
APPLY=0
CLEANUP_ACTION="scan"

usage() {
  cat <<'EOF'
Usage: bash bin/knot-planning.sh COMMAND [options]

Commands:
  init
  resolve
  close
  cleanup scan
  cleanup delete --dry-run|--apply

Options:
  --root DIR
  --scope root|direct|group
  --actor-user SLUG
  --group-slug SLUG
  --task-id ID
  --now ISO_TIMESTAMP
EOF
}

json_value() {
  local file="$1"
  local key="$2"
  jq -r --arg key "$key" '.[$key] // ""' "$file"
}

epoch_utc() {
  local value="$1"
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$value" '+%s' 2>/dev/null ||
    date -u -d "$value" '+%s'
}

task_root() {
  knot_scope_task_root "$ROOT" "$SCOPE" "$USER_SLUG" "$GROUP_SLUG"
}

active_file() {
  printf '%s\n' "$(task_root)/.active_task"
}

reject_symlink_components() {
  local path="$1"
  local rel
  local current="$ROOT"
  local part
  local parts=()

  case "$path" in
    "$ROOT"/*)
      rel="${path#"$ROOT"/}"
      ;;
    *)
      die "planning path is outside Knot root: $path"
      ;;
  esac
  IFS='/' read -r -a parts <<< "$rel"
  for part in "${parts[@]}"; do
    current="$current/$part"
    [ ! -L "$current" ] || die "planning path must not include symlinks: $current"
  done
}

task_dir() {
  [ -n "$TASK_ID" ] || die "--task-id or PLAN_ID is required"
  validate_slug "--task-id" "$TASK_ID"
  printf '%s\n' "$(task_root)/$TASK_ID"
}

write_default_plan() {
  local dir="$1"

  cat > "$dir/task_plan.md" <<'EOF'
# Task Plan

## Phases

### Phase 1: Requirements & Discovery
- [ ] Understand user intent
- **Status:** in_progress

### Phase 2: Implementation
- [ ] Execute scoped changes
- **Status:** pending

### Phase 3: Verification
- [ ] Run required checks
- **Status:** pending
EOF
  cat > "$dir/findings.md" <<'EOF'
# Findings

-
EOF
  cat > "$dir/progress.md" <<'EOF'
# Progress

-
EOF
}

write_meta() {
  local path="$1"
  local status="$2"
  local created_at="$3"
  local updated_at="$4"
  local closed_at="${5:-}"

  cat > "$path" <<EOF
{
  "task_id": "$TASK_ID",
  "scope": "$SCOPE",
  "actor_user": "$USER_SLUG",
  "group_slug": "$GROUP_SLUG",
  "status": "$status",
  "created_at": "$created_at",
  "updated_at": "$updated_at",
  "closed_at": "$closed_at"
}
EOF
}

update_meta_field() {
  local file="$1"
  local jq_expr="$2"
  local tmp

  tmp="$(mktemp "$file.tmp.XXXXXX")"
  jq "$jq_expr" "$file" > "$tmp"
  knot_atomic_replace "$tmp" "$file"
}

assert_task_tree_safe() {
  local dir="$1"

  [ ! -L "$dir" ] || die "planning task directory must not be a symlink: $dir"
  [ -d "$dir" ] || die "planning task directory is not a directory: $dir"
  if find "$dir" -type l -print -quit | grep -q .; then
    die "planning task directory must not contain symlinks: $dir"
  fi
}

is_active_task() {
  local id="$1"
  local active=""

  [ ! -L "$(active_file)" ] || die "planning active task pointer must not be a symlink"
  [ -f "$(active_file)" ] && active="$(tr -d '\r\n' < "$(active_file)")"
  [ "$id" = "$active" ] || { [ -n "${PLAN_ID:-}" ] && [ "$id" = "$PLAN_ID" ]; }
}

task_age_days() {
  local timestamp="$1"
  local timestamp_epoch
  local now_epoch

  timestamp_epoch="$(epoch_utc "$timestamp")"
  now_epoch="$(epoch_utc "$NOW")"
  printf '%s\n' $(( (now_epoch - timestamp_epoch) / 86400 ))
}

report_scan_one() {
  local dir="$1"
  local id
  local meta
  local status
  local updated_at
  local closed_at

  assert_task_tree_safe "$dir"
  id="$(basename "$dir")"
  meta="$dir/task.meta.json"
  [ -f "$meta" ] || return 0
  status="$(json_value "$meta" status)"

  case "$status" in
    active)
      ! is_active_task "$id" || return 0
      updated_at="$(json_value "$meta" updated_at)"
      [ -n "$updated_at" ] || return 0
      [ "$(task_age_days "$updated_at")" -ge 7 ] || return 0
      printf 'stale %s\n' "$id"
      ;;
    closed)
      closed_at="$(json_value "$meta" closed_at)"
      [ -n "$closed_at" ] || return 0
      [ "$(task_age_days "$closed_at")" -ge 7 ] || return 0
      printf 'delete %s\n' "$id"
      ;;
  esac
}

delete_one() {
  local dir="$1"
  local id
  local meta
  local status
  local closed_at

  id="$(basename "$dir")"
  assert_task_tree_safe "$dir"
  meta="$dir/task.meta.json"
  [ -f "$meta" ] || return 0
  status="$(json_value "$meta" status)"
  closed_at="$(json_value "$meta" closed_at)"
  [ "$status" = "closed" ] || return 0
  ! is_active_task "$id" || return 0
  [ -n "$closed_at" ] || return 0
  [ "$(task_age_days "$closed_at")" -ge 7 ] || return 0

  if [ "$APPLY" -eq 0 ]; then
    printf 'delete %s\n' "$id"
    return 0
  fi

  rm -rf "$dir"
  printf 'deleted: %s\n' "$id"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      shift; [ "$#" -gt 0 ] || die "--root requires a value"; ROOT="$1" ;;
    --scope)
      shift; [ "$#" -gt 0 ] || die "--scope requires a value"; SCOPE="$1" ;;
    --actor-user|--user-slug)
      shift; [ "$#" -gt 0 ] || die "--actor-user requires a value"; USER_SLUG="$1" ;;
    --group-slug)
      shift; [ "$#" -gt 0 ] || die "--group-slug requires a value"; GROUP_SLUG="$1" ;;
    --task-id)
      shift; [ "$#" -gt 0 ] || die "--task-id requires a value"; TASK_ID="$1" ;;
    --now)
      shift; [ "$#" -gt 0 ] || die "--now requires a value"; NOW="$1" ;;
    --dry-run)
      APPLY=0 ;;
    --apply)
      APPLY=1 ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      if [ "$COMMAND" = "cleanup" ] && [ -z "${CLEANUP_ACTION_SET:-}" ]; then
        CLEANUP_ACTION="$1"
        CLEANUP_ACTION_SET=1
      else
        die "unknown argument: $1"
      fi
      ;;
  esac
  shift
done

[ -n "$COMMAND" ] || die "command is required"
ROOT="$(cd "$ROOT" && pwd -P)"
reject_symlink_components "$(task_root)"

case "$COMMAND" in
  init)
    dir="$(task_dir)"
    [ ! -e "$dir" ] && [ ! -L "$dir" ] || die "task already exists: $dir"
    [ ! -L "$(active_file)" ] || die "planning active task pointer must not be a symlink"
    ensure_dir_no_symlink "$(task_root)" "planning task root"
    mkdir -p "$dir"
    write_default_plan "$dir"
    write_meta "$dir/task.meta.json" active "$NOW" "$NOW"
    printf '%s\n' "$TASK_ID" > "$(active_file)"
    printf '%s\n' "$dir"
    ;;
  resolve)
    root_dir="$(task_root)"
    active=""
    if [ -n "${PLAN_ID:-}" ]; then
      validate_slug "PLAN_ID" "$PLAN_ID"
    fi
    if [ -n "${PLAN_ID:-}" ] && [ -d "$root_dir/$PLAN_ID" ] && [ ! -L "$root_dir/$PLAN_ID" ]; then
      assert_task_tree_safe "$root_dir/$PLAN_ID"
      printf '%s\n' "$root_dir/$PLAN_ID"
      exit 0
    fi
    [ ! -L "$(active_file)" ] || die "planning active task pointer must not be a symlink"
    if [ -f "$(active_file)" ]; then
      active="$(tr -d '\r\n' < "$(active_file)")"
      validate_slug "active task id" "$active"
      if [ -n "$active" ] && [ -d "$root_dir/$active" ] && [ ! -L "$root_dir/$active" ]; then
        assert_task_tree_safe "$root_dir/$active"
        printf '%s\n' "$root_dir/$active"
      fi
    fi
    ;;
  close)
    dir="$(task_dir)"
    assert_task_tree_safe "$dir"
    [ -f "$dir/task.meta.json" ] || die "task metadata is missing: $dir"
    update_meta_field "$dir/task.meta.json" ".status = \"closed\" | .closed_at = \"$NOW\" | .updated_at = \"$NOW\""
    if [ -f "$(active_file)" ] && [ "$(tr -d '\r\n' < "$(active_file)")" = "$TASK_ID" ]; then
      rm -f "$(active_file)"
    fi
    printf '%s\n' "$dir"
    ;;
  cleanup)
    case "$CLEANUP_ACTION" in
      scan|delete)
        [ -d "$(task_root)" ] || exit 0
        for dir in "$(task_root)"/*; do
          [ -d "$dir" ] || continue
          if [ "$CLEANUP_ACTION" = "scan" ]; then
            report_scan_one "$dir"
          else
            delete_one "$dir"
          fi
        done
        ;;
      *)
        die "unknown cleanup action: $CLEANUP_ACTION"
        ;;
    esac
    ;;
  *)
    die "unknown command: $COMMAND"
    ;;
esac
