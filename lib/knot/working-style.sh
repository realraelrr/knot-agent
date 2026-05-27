# shellcheck shell=bash

# Callers must implement working_style_deny REASON MESSAGE so each operation records
# its own compact denial event before terminating.

working_style_relative_to_root() {
  local path="$1"
  local abs

  abs="$(absolute_path "$path")" || return 1
  case "$abs" in
    "$ROOT_REAL"/*)
      printf '%s\n' "${abs#"$ROOT_REAL/"}"
      ;;
    *)
      return 1
      ;;
  esac
}

working_style_ensure_owner_only_file() {
  local path="$1"

  if [ -L "$path" ]; then
    working_style_deny symlink_denied "working style must not be a symlink: $path"
  fi
  if [ -e "$path" ] && [ ! -f "$path" ]; then
    working_style_deny invalid_resource "working style path is not a file: $path"
  fi
  if [ ! -f "$path" ]; then
    : > "$path"
  fi
  chmod 600 "$path"
}

working_style_validate_content() {
  local path="$1"
  local validation_mode="${2:-read}"
  local source_block_pattern='^[[:space:]]*```[[:space:]]*(transcript|chat[-_ ]?log|conversation[-_ ]?log|source[-_ ]?document)'
  local secret_pattern='^[[:space:]]*([-*+][[:space:]]+|[0-9]+[.)][[:space:]]+)?(export[[:space:]]+)?(api[_-]?key|access[_-]?token|auth[_-]?token|secret|password|bearer[_-]?token)[[:space:]]*[:=][[:space:]]*[^[:space:]]+'
  local char_count

  if grep -Eiq "$source_block_pattern" "$path"; then
    working_style_deny working_style_content_denied "working style contains a transcript or source-document block"
  fi
  if grep -Eiq "$secret_pattern" "$path"; then
    working_style_deny working_style_content_denied "working style contains a secrets-looking assignment"
  fi
  char_count="$(wc -m < "$path" | tr -d '[:space:]')"
  [ "$char_count" -le 1600 ] ||
    working_style_deny working_style_content_denied "working style exceeds 1600 characters"
  if [ -x "$KNOT_COMMAND_ROOT/bin/knot-working-style-lint.sh" ]; then
    if [ "$validation_mode" = "write" ]; then
      if ! bash "$KNOT_COMMAND_ROOT/bin/knot-working-style-lint.sh" lint \
        --root "$ROOT" \
        --style "$path" \
        --require-structured >/dev/null 2>&1; then
        working_style_deny working_style_content_denied "working style schema validation failed"
      fi
    elif [ "$(sed -n '1p' "$path")" = "---" ] &&
      ! bash "$KNOT_COMMAND_ROOT/bin/knot-working-style-lint.sh" lint \
        --root "$ROOT" \
        --style "$path" \
        --enforce-if-frontmatter >/dev/null 2>&1; then
      working_style_deny working_style_content_denied "working style schema validation failed"
    fi
  fi
}

working_style_validate_identity_matches_actor() {
  local label="$1"
  local matches="$2"
  local required="$3"
  local count
  local resolved_workspace

  count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
  case "$count" in
    0)
      [ "$required" -eq 0 ] && return 0
      working_style_deny working_style_identity_unresolved "$label is not mapped in permissions"
      ;;
    1)
      resolved_workspace="$(printf '%s\n' "$matches" | sed '/^$/d' | head -n 1)"
      [ "$resolved_workspace" = "$USER_SLUG" ] ||
        working_style_deny working_style_workspace_mismatch "$label workspace does not match actor"
      ;;
    *)
      working_style_deny working_style_identity_ambiguous "$label maps to multiple workspaces"
      ;;
  esac
}

working_style_validate_permissions_actor_scope() {
  local permissions_file="$ROOT/workspace/admin/permissions.md"

  [ -f "$permissions_file" ] ||
    working_style_deny working_style_identity_unresolved "permissions source of truth is missing"
  if [ -n "$IDENTITY_KEY" ]; then
    working_style_validate_identity_matches_actor "identity key" "$(permissions_actor_workspaces_by_identity_key "$ROOT" "$IDENTITY_KEY")" 1
    working_style_validate_identity_matches_actor "platform user id" "$(permissions_actor_workspaces_by_platform_user "$ROOT" "$PLATFORM" "$USER_ID")" 0
  else
    working_style_validate_identity_matches_actor "platform user id" "$(permissions_actor_workspaces_by_platform_user "$ROOT" "$PLATFORM" "$USER_ID")" 1
  fi
}

working_style_deny_if_symlink() {
  local path="$1"
  local label="$2"

  if [ -L "$path" ]; then
    working_style_deny symlink_denied "$label must not be a symlink: $path"
  fi
}

working_style_validate_actor_scope() {
  local expected_user_workspace
  local expected_group_workspace
  local expected_actor_workspace

  [ -n "$USER_SLUG" ] ||
    working_style_deny working_style_identity_unresolved "--actor-user or KNOT_ACTOR_USER is required"
  if [ -z "${SCOPE:-}" ]; then
    if [ -n "$GROUP_SLUG" ]; then
      working_style_deny working_style_workspace_mismatch "group slug requires explicit group scope"
    fi
    SCOPE="direct"
  fi
  validate_slug "--actor-user" "$USER_SLUG"
  [ -z "$GROUP_SLUG" ] || validate_slug "--group-slug" "$GROUP_SLUG"
  case "$SCOPE" in
    direct|group)
      ;;
    *)
      working_style_deny working_style_workspace_mismatch "KNOT_SCOPE must be direct or group"
      ;;
  esac
  if [ "$SCOPE" = "direct" ] && [ -n "$GROUP_SLUG" ]; then
    working_style_deny working_style_workspace_mismatch "direct scope cannot include a group slug"
  fi
  working_style_validate_permissions_actor_scope

  expected_user_workspace="$ROOT/workspace/users/$USER_SLUG"
  expected_group_workspace=""
  expected_actor_workspace="$expected_user_workspace"
  if [ "$SCOPE" = "group" ]; then
    [ -n "$GROUP_SLUG" ] ||
      working_style_deny working_style_workspace_mismatch "group scope requires --group-slug or KNOT_GROUP_SLUG"
    permissions_group_authorized "$ROOT" "$PLATFORM" "$USER_ID" "$CHAT_ID" "$IDENTITY_KEY" "$GROUP_SLUG" ||
      working_style_deny working_style_workspace_mismatch "group workspace is not authorized for this actor/context"
    expected_group_workspace="$ROOT/workspace/groups/$GROUP_SLUG"
    expected_actor_workspace="$expected_group_workspace/work/$USER_SLUG"
  fi
  if [ "$SCOPE" = "direct" ] && [ "${EXPLICIT_ACTOR_WORKSPACE:-0}" -eq 0 ]; then
    ACTOR_WORKSPACE="$expected_actor_workspace"
  fi

  [ -n "$USER_WORKSPACE" ] ||
    working_style_deny working_style_identity_unresolved "--user-workspace or KNOT_USER_WORKSPACE is required"
  [ -n "$ACTIVE_WORKSPACE" ] ||
    working_style_deny working_style_identity_unresolved "--active-workspace or KNOT_ACTIVE_WORKSPACE is required"
  [ -n "${ACTOR_WORKSPACE:-}" ] ||
    ACTOR_WORKSPACE="$expected_actor_workspace"

  USER_WORKSPACE="$(absolute_path "$USER_WORKSPACE")" ||
    working_style_deny working_style_workspace_mismatch "cannot resolve user workspace"
  ACTIVE_WORKSPACE="$(absolute_path "$ACTIVE_WORKSPACE")" ||
    working_style_deny working_style_workspace_mismatch "cannot resolve active workspace"
  ACTOR_WORKSPACE="$(absolute_path "$ACTOR_WORKSPACE")" ||
    working_style_deny working_style_workspace_mismatch "cannot resolve actor workspace"
  expected_user_workspace="$(absolute_path "$expected_user_workspace")" ||
    working_style_deny working_style_workspace_mismatch "cannot resolve expected user workspace"
  expected_actor_workspace="$(absolute_path "$expected_actor_workspace")" ||
    working_style_deny working_style_workspace_mismatch "cannot resolve expected actor workspace"

  [ "$USER_WORKSPACE" = "$expected_user_workspace" ] ||
    working_style_deny working_style_workspace_mismatch "user workspace does not match actor"
  [ "$ACTOR_WORKSPACE" = "$expected_actor_workspace" ] ||
    working_style_deny working_style_workspace_mismatch "actor workspace does not match scope"
  if [ "$SCOPE" = "direct" ]; then
    [ "$ACTIVE_WORKSPACE" = "$USER_WORKSPACE" ] ||
      working_style_deny working_style_workspace_mismatch "active workspace must equal user workspace for direct working style"
  else
    expected_group_workspace="$(absolute_path "$expected_group_workspace")" ||
      working_style_deny working_style_workspace_mismatch "cannot resolve expected group workspace"
    [ "$ACTIVE_WORKSPACE" = "$expected_group_workspace" ] ||
      working_style_deny working_style_workspace_mismatch "active workspace must equal group workspace for group working style pack"
  fi

  working_style_deny_if_symlink "$ROOT/workspace" "workspace root"
  working_style_deny_if_symlink "$ROOT/workspace/users" "users root"
  working_style_deny_if_symlink "$USER_WORKSPACE" "user workspace"
  if [ "$SCOPE" = "group" ]; then
    working_style_deny_if_symlink "$ROOT/workspace/groups" "groups root"
    working_style_deny_if_symlink "$ACTIVE_WORKSPACE" "group workspace"
    working_style_deny_if_symlink "$ACTOR_WORKSPACE" "group actor workspace"
  fi
}
