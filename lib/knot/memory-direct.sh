# shellcheck shell=bash

# Callers must implement memory_deny REASON MESSAGE so each operation records
# its own compact denial event before terminating.

memory_relative_to_root() {
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

memory_ensure_owner_only_file() {
  local path="$1"

  if [ -L "$path" ]; then
    memory_deny symlink_denied "memory file must not be a symlink: $path"
  fi
  if [ -e "$path" ] && [ ! -f "$path" ]; then
    memory_deny invalid_resource "memory path is not a file: $path"
  fi
  if [ ! -f "$path" ]; then
    : > "$path"
  fi
  chmod 600 "$path"
}

memory_permissions_actor_workspace_by_identity_key() {
  local permissions_file="$ROOT/workspace/admin/permissions.md"

  [ -f "$permissions_file" ] || return 0
  awk -F'|' \
    -v identity_key="$IDENTITY_KEY" '
    function trim(s) {
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      return s
    }
    NR < 3 || $0 !~ /^\|/ { next }
    {
      workspace = trim($3)
      row_identity_key = trim($8)
      if (workspace == "Workspace" || workspace == "---" || workspace == "") {
        next
      }

      if (identity_key != "" && row_identity_key != "" && row_identity_key == identity_key) {
        print workspace
      }
    }
  ' "$permissions_file" | sort -u
}

memory_permissions_actor_workspace_by_platform_user() {
  local permissions_file="$ROOT/workspace/admin/permissions.md"

  [ -f "$permissions_file" ] || return 0
  awk -F'|' \
    -v platform="$PLATFORM" \
    -v user_id="$USER_ID" '
    function trim(s) {
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      return s
    }
    NR < 3 || $0 !~ /^\|/ { next }
    {
      workspace = trim($3)
      row_platform = trim($4)
      row_user_id = trim($5)
      if (workspace == "Workspace" || workspace == "---" || workspace == "") {
        next
      }

      if (platform != "" && user_id != "" && row_platform == platform && row_user_id == user_id) {
        print workspace
      }
    }
  ' "$permissions_file" | sort -u
}

memory_validate_identity_matches_actor() {
  local label="$1"
  local matches="$2"
  local required="$3"
  local count
  local resolved_workspace

  count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
  case "$count" in
    0)
      [ "$required" -eq 0 ] && return 0
      memory_deny memory_identity_unresolved "$label is not mapped in permissions"
      ;;
    1)
      resolved_workspace="$(printf '%s\n' "$matches" | sed '/^$/d' | head -n 1)"
      [ "$resolved_workspace" = "$USER_SLUG" ] ||
        memory_deny memory_workspace_mismatch "$label workspace does not match actor"
      ;;
    *)
      memory_deny memory_identity_ambiguous "$label maps to multiple workspaces"
      ;;
  esac
}

memory_validate_permissions_actor_scope() {
  local permissions_file="$ROOT/workspace/admin/permissions.md"

  [ -f "$permissions_file" ] ||
    memory_deny memory_identity_unresolved "permissions source of truth is missing"
  if [ -n "$IDENTITY_KEY" ]; then
    memory_validate_identity_matches_actor "identity key" "$(memory_permissions_actor_workspace_by_identity_key)" 1
    memory_validate_identity_matches_actor "platform user id" "$(memory_permissions_actor_workspace_by_platform_user)" 0
  else
    memory_validate_identity_matches_actor "platform user id" "$(memory_permissions_actor_workspace_by_platform_user)" 1
  fi
}

memory_deny_if_symlink() {
  local path="$1"
  local label="$2"

  if [ -L "$path" ]; then
    memory_deny symlink_denied "$label must not be a symlink: $path"
  fi
}

memory_validate_direct_scope() {
  local expected_user_workspace

  [ -n "$USER_SLUG" ] ||
    memory_deny memory_identity_unresolved "--actor-user or KNOT_ACTOR_USER is required"
  validate_slug "--actor-user" "$USER_SLUG"
  [ -z "$GROUP_SLUG" ] || validate_slug "--group-slug" "$GROUP_SLUG"
  [ -z "$GROUP_SLUG" ] ||
    memory_deny unauthorized_group "group-scoped memory is not implemented yet"
  memory_validate_permissions_actor_scope

  expected_user_workspace="$ROOT/workspace/users/$USER_SLUG"
  [ -n "$USER_WORKSPACE" ] ||
    memory_deny memory_identity_unresolved "--user-workspace or KNOT_USER_WORKSPACE is required"
  [ -n "$ACTIVE_WORKSPACE" ] ||
    memory_deny memory_identity_unresolved "--active-workspace or KNOT_ACTIVE_WORKSPACE is required"

  USER_WORKSPACE="$(absolute_path "$USER_WORKSPACE")" ||
    memory_deny memory_workspace_mismatch "cannot resolve user workspace"
  ACTIVE_WORKSPACE="$(absolute_path "$ACTIVE_WORKSPACE")" ||
    memory_deny memory_workspace_mismatch "cannot resolve active workspace"
  expected_user_workspace="$(absolute_path "$expected_user_workspace")" ||
    memory_deny memory_workspace_mismatch "cannot resolve expected user workspace"

  [ "$USER_WORKSPACE" = "$expected_user_workspace" ] ||
    memory_deny memory_workspace_mismatch "user workspace does not match actor"
  [ "$ACTIVE_WORKSPACE" = "$USER_WORKSPACE" ] ||
    memory_deny memory_workspace_mismatch "active workspace must equal user workspace for direct memory"

  memory_deny_if_symlink "$ROOT/workspace" "workspace root"
  memory_deny_if_symlink "$ROOT/workspace/users" "users root"
  memory_deny_if_symlink "$USER_WORKSPACE" "user workspace"
}
