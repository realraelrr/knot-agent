# shellcheck shell=bash

# Callers must implement collab_profile_deny REASON MESSAGE so each operation records
# its own compact denial event before terminating.

collab_profile_relative_to_root() {
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

collab_profile_ensure_owner_only_file() {
  local path="$1"

  if [ -L "$path" ]; then
    collab_profile_deny symlink_denied "collaborator profile must not be a symlink: $path"
  fi
  if [ -e "$path" ] && [ ! -f "$path" ]; then
    collab_profile_deny invalid_resource "collaborator profile path is not a file: $path"
  fi
  if [ ! -f "$path" ]; then
    : > "$path"
  fi
  chmod 600 "$path"
}

collab_profile_validate_content() {
  local path="$1"
  local validation_mode="${2:-read}"
  local source_block_pattern='^[[:space:]]*```[[:space:]]*(transcript|chat[-_ ]?log|conversation[-_ ]?log|source[-_ ]?document)'
  local secret_pattern='^[[:space:]]*([-*+][[:space:]]+|[0-9]+[.)][[:space:]]+)?(export[[:space:]]+)?(api[_-]?key|access[_-]?token|auth[_-]?token|secret|password|bearer[_-]?token)[[:space:]]*[:=][[:space:]]*[^[:space:]]+'
  local char_count

  if grep -Eiq "$source_block_pattern" "$path"; then
    collab_profile_deny collab_profile_content_denied "collaborator profile contains a transcript or source-document block"
  fi
  if grep -Eiq "$secret_pattern" "$path"; then
    collab_profile_deny collab_profile_content_denied "collaborator profile contains a secrets-looking assignment"
  fi
  char_count="$(wc -m < "$path" | tr -d '[:space:]')"
  [ "$char_count" -le 1600 ] ||
    collab_profile_deny collab_profile_content_denied "collaborator profile exceeds 1600 characters"
  if [ -x "$KNOT_COMMAND_ROOT/bin/knot-collaborator-profile-lint.sh" ]; then
    if [ "$validation_mode" = "write" ]; then
      if ! bash "$KNOT_COMMAND_ROOT/bin/knot-collaborator-profile-lint.sh" lint \
        --root "$ROOT" \
        --profile "$path" \
        --require-structured >/dev/null 2>&1; then
        collab_profile_deny collab_profile_content_denied "collaborator profile schema validation failed"
      fi
    elif [ "$(sed -n '1p' "$path")" = "---" ] &&
      ! bash "$KNOT_COMMAND_ROOT/bin/knot-collaborator-profile-lint.sh" lint \
        --root "$ROOT" \
        --profile "$path" \
        --enforce-if-frontmatter >/dev/null 2>&1; then
      collab_profile_deny collab_profile_content_denied "collaborator profile schema validation failed"
    fi
  fi
}

collab_profile_validate_identity_matches_actor() {
  local label="$1"
  local matches="$2"
  local required="$3"
  local count
  local resolved_workspace

  count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
  case "$count" in
    0)
      [ "$required" -eq 0 ] && return 0
      collab_profile_deny collab_profile_identity_unresolved "$label is not mapped in permissions"
      ;;
    1)
      resolved_workspace="$(printf '%s\n' "$matches" | sed '/^$/d' | head -n 1)"
      [ "$resolved_workspace" = "$USER_SLUG" ] ||
        collab_profile_deny collab_profile_workspace_mismatch "$label workspace does not match actor"
      ;;
    *)
      collab_profile_deny collab_profile_identity_ambiguous "$label maps to multiple workspaces"
      ;;
  esac
}

collab_profile_validate_permissions_actor_scope() {
  local permissions_file="$ROOT/workspace/admin/permissions.md"

  [ -f "$permissions_file" ] ||
    collab_profile_deny collab_profile_identity_unresolved "permissions source of truth is missing"
  if [ -n "$IDENTITY_KEY" ]; then
    collab_profile_validate_identity_matches_actor "identity key" "$(permissions_actor_workspaces_by_identity_key "$ROOT" "$IDENTITY_KEY")" 1
    collab_profile_validate_identity_matches_actor "platform user id" "$(permissions_actor_workspaces_by_platform_user "$ROOT" "$PLATFORM" "$USER_ID")" 0
  else
    collab_profile_validate_identity_matches_actor "platform user id" "$(permissions_actor_workspaces_by_platform_user "$ROOT" "$PLATFORM" "$USER_ID")" 1
  fi
}

collab_profile_deny_if_symlink() {
  local path="$1"
  local label="$2"

  if [ -L "$path" ]; then
    collab_profile_deny symlink_denied "$label must not be a symlink: $path"
  fi
}

collab_profile_validate_actor_scope() {
  local expected_user_workspace
  local expected_group_workspace
  local expected_actor_workspace

  [ -n "$USER_SLUG" ] ||
    collab_profile_deny collab_profile_identity_unresolved "--actor-user or KNOT_ACTOR_USER is required"
  if [ -z "${SCOPE:-}" ]; then
    if [ -n "$GROUP_SLUG" ]; then
      collab_profile_deny collab_profile_workspace_mismatch "group slug requires explicit group scope"
    fi
    SCOPE="direct"
  fi
  validate_slug "--actor-user" "$USER_SLUG"
  [ -z "$GROUP_SLUG" ] || validate_slug "--group-slug" "$GROUP_SLUG"
  case "$SCOPE" in
    direct|group)
      ;;
    *)
      collab_profile_deny collab_profile_workspace_mismatch "KNOT_SCOPE must be direct or group"
      ;;
  esac
  if [ "$SCOPE" = "direct" ] && [ -n "$GROUP_SLUG" ]; then
    collab_profile_deny collab_profile_workspace_mismatch "direct scope cannot include a group slug"
  fi
  collab_profile_validate_permissions_actor_scope

  expected_user_workspace="$ROOT/workspace/users/$USER_SLUG"
  expected_group_workspace=""
  expected_actor_workspace="$expected_user_workspace"
  if [ "$SCOPE" = "group" ]; then
    [ -n "$GROUP_SLUG" ] ||
      collab_profile_deny collab_profile_workspace_mismatch "group scope requires --group-slug or KNOT_GROUP_SLUG"
    permissions_can_use_group "$ROOT" "$PLATFORM" "$USER_ID" "$CHAT_ID" "$IDENTITY_KEY" "$GROUP_SLUG" ||
      collab_profile_deny collab_profile_workspace_mismatch "group workspace is not authorized for this actor/context"
    expected_group_workspace="$ROOT/workspace/groups/$GROUP_SLUG"
    expected_actor_workspace="$expected_group_workspace/work/$USER_SLUG"
  fi
  if [ "$SCOPE" = "direct" ] && [ "${EXPLICIT_ACTOR_WORKSPACE:-0}" -eq 0 ]; then
    ACTOR_WORKSPACE="$expected_actor_workspace"
  fi

  [ -n "$USER_WORKSPACE" ] ||
    collab_profile_deny collab_profile_identity_unresolved "--user-workspace or KNOT_USER_WORKSPACE is required"
  [ -n "$ACTIVE_WORKSPACE" ] ||
    collab_profile_deny collab_profile_identity_unresolved "--active-workspace or KNOT_ACTIVE_WORKSPACE is required"
  [ -n "${ACTOR_WORKSPACE:-}" ] ||
    ACTOR_WORKSPACE="$expected_actor_workspace"

  USER_WORKSPACE="$(absolute_path "$USER_WORKSPACE")" ||
    collab_profile_deny collab_profile_workspace_mismatch "cannot resolve user workspace"
  ACTIVE_WORKSPACE="$(absolute_path "$ACTIVE_WORKSPACE")" ||
    collab_profile_deny collab_profile_workspace_mismatch "cannot resolve active workspace"
  ACTOR_WORKSPACE="$(absolute_path "$ACTOR_WORKSPACE")" ||
    collab_profile_deny collab_profile_workspace_mismatch "cannot resolve actor workspace"
  expected_user_workspace="$(absolute_path "$expected_user_workspace")" ||
    collab_profile_deny collab_profile_workspace_mismatch "cannot resolve expected user workspace"
  expected_actor_workspace="$(absolute_path "$expected_actor_workspace")" ||
    collab_profile_deny collab_profile_workspace_mismatch "cannot resolve expected actor workspace"

  [ "$USER_WORKSPACE" = "$expected_user_workspace" ] ||
    collab_profile_deny collab_profile_workspace_mismatch "user workspace does not match actor"
  [ "$ACTOR_WORKSPACE" = "$expected_actor_workspace" ] ||
    collab_profile_deny collab_profile_workspace_mismatch "actor workspace does not match scope"
  if [ "$SCOPE" = "direct" ]; then
    [ "$ACTIVE_WORKSPACE" = "$USER_WORKSPACE" ] ||
      collab_profile_deny collab_profile_workspace_mismatch "active workspace must equal user workspace for direct collaborator profile"
  else
    expected_group_workspace="$(absolute_path "$expected_group_workspace")" ||
      collab_profile_deny collab_profile_workspace_mismatch "cannot resolve expected group workspace"
    [ "$ACTIVE_WORKSPACE" = "$expected_group_workspace" ] ||
      collab_profile_deny collab_profile_workspace_mismatch "active workspace must equal group workspace for group collaborator profile pack"
  fi

  collab_profile_deny_if_symlink "$ROOT/workspace" "workspace root"
  collab_profile_deny_if_symlink "$ROOT/workspace/users" "users root"
  collab_profile_deny_if_symlink "$USER_WORKSPACE" "user workspace"
  if [ "$SCOPE" = "group" ]; then
    collab_profile_deny_if_symlink "$ROOT/workspace/groups" "groups root"
    collab_profile_deny_if_symlink "$ACTIVE_WORKSPACE" "group workspace"
    collab_profile_deny_if_symlink "$ACTOR_WORKSPACE" "group actor workspace"
  fi
}
