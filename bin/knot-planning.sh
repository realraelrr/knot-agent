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

usage() {
  cat <<'EOF'
Usage: bash bin/knot-planning.sh COMMAND [options]

Commands:
  init | resolve | close | pin | unpin | restore
  cleanup scan
  cleanup archive --dry-run|--apply
  cleanup expire --dry-run|--apply

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

state_root() {
  knot_scope_state_root "$ROOT" "$SCOPE" "$USER_SLUG" "$GROUP_SLUG"
}

archive_root() {
  knot_scope_task_archive_root "$ROOT" "$SCOPE" "$USER_SLUG" "$GROUP_SLUG"
}

tombstone_root() {
  knot_scope_task_tombstone_root "$ROOT" "$SCOPE" "$USER_SLUG" "$GROUP_SLUG"
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
  local pinned="$3"
  local created_at="$4"
  local updated_at="$5"
  local closed_at="${6:-}"
  local archived_at="${7:-}"
  local expires_at="${8:-}"

  cat > "$path" <<EOF
{
  "task_id": "$TASK_ID",
  "scope": "$SCOPE",
  "actor_user": "$USER_SLUG",
  "group_slug": "$GROUP_SLUG",
  "status": "$status",
  "pinned": $pinned,
  "created_at": "$created_at",
  "updated_at": "$updated_at",
  "closed_at": "$closed_at",
  "archived_at": "$archived_at",
  "expires_at": "$expires_at"
}
EOF
}

update_meta_field() {
  local file="$1"
  local jq_expr="$2"
  local tmp

  tmp="$(mktemp "$file.tmp.XXXXXX")"
  jq "$jq_expr" "$file" > "$tmp"
  mv "$tmp" "$file"
}

has_open_phase() {
  local dir="$1"
  grep -Eq '\*\*Status:\*\* (pending|in_progress)' "$dir/task_plan.md"
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

write_archive_manifest() {
  local dir="$1"

  knot_manifest_write_dir "$dir" "$dir/archive-manifest.tsv"
}

verify_archive_manifest() {
  local dir="$1"

  assert_task_tree_safe "$dir"
  knot_manifest_verify_dir "$dir" "$dir/archive-manifest.tsv" "planning archive manifest"
}

report_stale_one() {
  local dir="$1"
  local id
  local meta
  local status
  local pinned
  local updated_at
  local updated_epoch
  local now_epoch
  local age_days

  assert_task_tree_safe "$dir"
  id="$(basename "$dir")"
  meta="$dir/task.meta.json"
  [ -f "$meta" ] || return 0
  status="$(json_value "$meta" status)"
  pinned="$(jq -r '.pinned // false' "$meta")"
  updated_at="$(json_value "$meta" updated_at)"
  [ "$status" = "active" ] || return 0
  [ "$pinned" != "true" ] || return 0
  ! is_active_task "$id" || return 0
  [ -n "$updated_at" ] || return 0
  updated_epoch="$(epoch_utc "$updated_at")"
  now_epoch="$(epoch_utc "$NOW")"
  age_days=$(( (now_epoch - updated_epoch) / 86400 ))
  [ "$age_days" -ge 7 ] || return 0
  printf 'stale %s\n' "$id"
}

archive_one() {
  local dir="$1"
  local id
  local meta
  local status
  local pinned
  local closed_at
  local closed_epoch
  local now_epoch
  local age_days
  local dest
  local expires

  id="$(basename "$dir")"
  assert_task_tree_safe "$dir"
  meta="$dir/task.meta.json"
  [ -f "$meta" ] || return 0
  status="$(json_value "$meta" status)"
  pinned="$(jq -r '.pinned // false' "$meta")"
  closed_at="$(json_value "$meta" closed_at)"
  [ "$status" = "closed" ] || return 0
  [ "$pinned" != "true" ] || return 0
  ! is_active_task "$id" || return 0
  ! has_open_phase "$dir" || return 0
  [ -n "$closed_at" ] || return 0
  closed_epoch="$(epoch_utc "$closed_at")"
  now_epoch="$(epoch_utc "$NOW")"
  age_days=$(( (now_epoch - closed_epoch) / 86400 ))
  [ "$age_days" -ge 7 ] || return 0

  if [ "$APPLY" -eq 0 ]; then
    printf 'archive %s\n' "$id"
    return 0
  fi

  dest="$(archive_root)/$id"
  [ ! -e "$dest" ] && [ ! -L "$dest" ] || die "archive destination already exists: $dest"
  ensure_dir_no_symlink "$(archive_root)" "planning archive root"
  mv "$dir" "$dest"
  TASK_ID="$id"
  expires="$(date -u -j -v+90d -f '%Y-%m-%dT%H:%M:%SZ' "$NOW" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null ||
    date -u -d "$NOW + 90 days" '+%Y-%m-%dT%H:%M:%SZ')"
  update_meta_field "$dest/task.meta.json" ".status = \"archived\" | .archived_at = \"$NOW\" | .expires_at = \"$expires\" | .updated_at = \"$NOW\""
  write_archive_manifest "$dest"
  printf 'archived: %s\n' "$dest"
}

expire_one() {
  local dir="$1"
  local id
  local meta
  local pinned
  local status
  local expires_at
  local expires_epoch
  local now_epoch
  local tombstone
  local tmp_tombstone

  id="$(basename "$dir")"
  assert_task_tree_safe "$dir"
  meta="$dir/task.meta.json"
  [ -f "$meta" ] || return 0
  status="$(json_value "$meta" status)"
  [ "$status" = "archived" ] || return 0
  pinned="$(jq -r '.pinned // false' "$meta")"
  [ "$pinned" != "true" ] || return 0
  ! is_active_task "$id" || return 0
  expires_at="$(json_value "$meta" expires_at)"
  [ -n "$expires_at" ] || return 0
  expires_epoch="$(epoch_utc "$expires_at")"
  now_epoch="$(epoch_utc "$NOW")"
  [ "$now_epoch" -ge "$expires_epoch" ] || return 0
  verify_archive_manifest "$dir"

  if [ "$APPLY" -eq 0 ]; then
    printf 'expire %s\n' "$id"
    return 0
  fi

  ensure_dir_no_symlink "$(tombstone_root)" "planning tombstone root"
  tombstone="$(tombstone_root)/$id.json"
  [ ! -e "$tombstone" ] && [ ! -L "$tombstone" ] ||
    die "planning tombstone already exists or is unsafe: $tombstone"
  tmp_tombstone="$(mktemp "$(tombstone_root)/.$id.json.tmp.XXXXXX")"
  if ! jq --arg expired_at "$NOW" \
    --arg archive_path "${dir#"$ROOT/"}" \
    --arg manifest_sha256 "$(file_sha256 "$dir/archive-manifest.tsv")" \
    --rawfile manifest_tsv "$dir/archive-manifest.tsv" \
    '. + {expired_at: $expired_at, archive_path: $archive_path, manifest_sha256: $manifest_sha256, manifest_tsv: $manifest_tsv}' "$meta" > "$tmp_tombstone"; then
    rm -f "$tmp_tombstone"
    die "cannot write planning tombstone"
  fi
  knot_atomic_replace "$tmp_tombstone" "$tombstone"
  rm -rf "$dir"
  printf 'expired: %s\n' "$id"
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
      if [ "$COMMAND" = "cleanup" ] && [ -z "${CLEANUP_ACTION:-}" ]; then
        CLEANUP_ACTION="$1"
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
reject_symlink_components "$(archive_root)"
reject_symlink_components "$(tombstone_root)"

case "$COMMAND" in
  init)
    dir="$(task_dir)"
    [ ! -e "$dir" ] && [ ! -L "$dir" ] || die "task already exists: $dir"
    [ ! -L "$(active_file)" ] || die "planning active task pointer must not be a symlink"
    ensure_dir_no_symlink "$(task_root)" "planning task root"
    mkdir -p "$dir"
    write_default_plan "$dir"
    write_meta "$dir/task.meta.json" active false "$NOW" "$NOW"
    printf '%s\n' "$TASK_ID" > "$(active_file)"
    printf '%s\n' "$dir"
    ;;
  resolve)
    root_dir="$(task_root)"
    active=""
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
    ! has_open_phase "$dir" || die "cannot close task with pending or in_progress phases"
    update_meta_field "$dir/task.meta.json" ".status = \"closed\" | .closed_at = \"$NOW\" | .updated_at = \"$NOW\""
    if [ -f "$(active_file)" ] && [ "$(tr -d '\r\n' < "$(active_file)")" = "$TASK_ID" ]; then
      rm -f "$(active_file)"
    fi
    printf '%s\n' "$dir"
    ;;
  pin|unpin)
    dir="$(task_dir)"
    assert_task_tree_safe "$dir"
    [ -f "$dir/task.meta.json" ] || die "task metadata is missing: $dir"
    value=false
    [ "$COMMAND" = "pin" ] && value=true
    update_meta_field "$dir/task.meta.json" ".pinned = $value | .updated_at = \"$NOW\""
    printf '%s\n' "$dir"
    ;;
  restore)
    validate_slug "--task-id" "$TASK_ID"
    src="$(archive_root)/$TASK_ID"
    dest="$(task_root)/$TASK_ID"
    [ -d "$src" ] && [ ! -L "$src" ] || die "archive not found or is unsafe: $src"
    [ ! -e "$dest" ] && [ ! -L "$dest" ] || die "task destination already exists: $dest"
    verify_archive_manifest "$src"
    ensure_dir_no_symlink "$(task_root)" "planning task root"
    mv "$src" "$dest"
    update_meta_field "$dest/task.meta.json" ".status = \"closed\" | .updated_at = \"$NOW\""
    rm -f "$dest/archive-manifest.tsv"
    printf '%s\n' "$dest"
    ;;
  cleanup)
    action="${CLEANUP_ACTION:-scan}"
    case "$action" in
      scan|archive)
        [ -d "$(task_root)" ] || exit 0
        matched=0
        for dir in "$(task_root)"/*; do
          [ -d "$dir" ] || continue
          if [ "$action" = "scan" ]; then
            before_output="$(report_stale_one "$dir")"
            if [ -z "$before_output" ]; then
              saved_apply="$APPLY"
              APPLY=0
              before_output="$(archive_one "$dir")"
              APPLY="$saved_apply"
            fi
          else
            before_output="$(archive_one "$dir")"
          fi
          if [ -n "$before_output" ]; then
            matched=1
            printf '%s\n' "$before_output"
          fi
        done
        if [ "$action" = "archive" ] && [ "$APPLY" -eq 1 ] && [ "$matched" -eq 0 ]; then
          die "no archive candidates"
        fi
        ;;
      expire)
        [ -d "$(archive_root)" ] || exit 0
        matched=0
        for dir in "$(archive_root)"/*; do
          [ -d "$dir" ] || continue
          before_output="$(expire_one "$dir")"
          if [ -n "$before_output" ]; then
            matched=1
            printf '%s\n' "$before_output"
          fi
        done
        if [ "$APPLY" -eq 1 ] && [ "$matched" -eq 0 ]; then
          die "no expire candidates"
        fi
        ;;
      *)
        die "unknown cleanup action: $action"
        ;;
    esac
    ;;
  *)
    die "unknown command: $COMMAND"
    ;;
esac
