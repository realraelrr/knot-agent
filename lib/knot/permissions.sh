# shellcheck shell=bash

[ "${KNOT_PERMISSIONS_SH_LOADED:-0}" -eq 1 ] && return 0
KNOT_PERMISSIONS_SH_LOADED=1

permissions_file_for_root() {
  printf '%s\n' "$1/workspace/admin/permissions.md"
}

permissions_actor_workspaces_by_identity_key() {
  local root="$1"
  local identity_key="$2"
  local permissions_file

  [ -n "$identity_key" ] || return 0
  permissions_file="$(permissions_file_for_root "$root")"
  [ -f "$permissions_file" ] || return 0

  awk -F'|' -v identity_key="$identity_key" '
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
      if (row_identity_key != "" && row_identity_key == identity_key) {
        print workspace
      }
    }
  ' "$permissions_file" | sed '/^$/d' | sort -u
}

permissions_actor_workspaces_by_identity_context() {
  local root="$1"
  local platform="$2"
  local user_id="$3"
  local identity_key="$4"
  local permissions_file

  [ -n "$identity_key" ] || return 0
  permissions_file="$(permissions_file_for_root "$root")"
  [ -f "$permissions_file" ] || return 0

  awk -F'|' \
    -v platform="$platform" \
    -v user_id="$user_id" \
    -v identity_key="$identity_key" '
    function trim(s) {
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      return s
    }
    NR < 3 || $0 !~ /^\|/ { next }
    {
      workspace = trim($3)
      row_platform = trim($4)
      row_user_id = trim($5)
      row_identity_key = trim($8)
      if (workspace == "Workspace" || workspace == "---" || workspace == "") {
        next
      }
      if (row_identity_key != "" &&
          row_identity_key == identity_key &&
          (row_platform == "" || platform == "" || row_platform == platform) &&
          (row_user_id == "" || user_id == "" || row_user_id == user_id)) {
        print workspace
      }
    }
  ' "$permissions_file" | sed '/^$/d' | sort -u
}

permissions_actor_workspaces_by_platform_user() {
  local root="$1"
  local platform="$2"
  local user_id="$3"
  local permissions_file

  [ -n "$platform" ] && [ -n "$user_id" ] || return 0
  permissions_file="$(permissions_file_for_root "$root")"
  [ -f "$permissions_file" ] || return 0

  awk -F'|' -v platform="$platform" -v user_id="$user_id" '
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
      if (row_platform == platform && row_user_id == user_id) {
        print workspace
      }
    }
  ' "$permissions_file" | sed '/^$/d' | sort -u
}

permissions_actor_workspaces() {
  local root="$1"
  local platform="$2"
  local user_id="$3"
  local identity_key="$4"

  if [ -n "$identity_key" ]; then
    permissions_actor_workspaces_by_identity_context "$root" "$platform" "$user_id" "$identity_key"
  else
    permissions_actor_workspaces_by_platform_user "$root" "$platform" "$user_id"
  fi
}

permissions_groups_for_actor_chat() {
  local root="$1"
  local platform="$2"
  local user_id="$3"
  local chat_id="$4"
  local identity_key="$5"
  local permissions_file

  [ -n "$chat_id" ] || return 0
  permissions_file="$(permissions_file_for_root "$root")"
  [ -f "$permissions_file" ] || return 0

  awk -F'|' \
    -v platform="$platform" \
    -v user_id="$user_id" \
    -v chat_id="$chat_id" \
    -v identity_key="$identity_key" '
    function trim(s) {
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      return s
    }
    NR < 3 || $0 !~ /^\|/ { next }
    {
      row_platform = trim($4)
      row_user_id = trim($5)
      group_slug = trim($6)
      row_chat_id = trim($7)
      row_identity_key = trim($8)
      if (group_slug == "" || group_slug == "Group" || group_slug == "---") {
        next
      }
      if (identity_key != "") {
        actor_match = (row_identity_key != "" &&
          row_identity_key == identity_key &&
          (row_user_id == "" || user_id == "" || row_user_id == user_id))
      } else {
        actor_match = (row_platform == platform && row_user_id == user_id)
      }
      if (row_platform == platform && row_chat_id == chat_id && actor_match) {
        print group_slug
      }
    }
  ' "$permissions_file" | sed '/^$/d' | sort -u
}

permissions_actor_roles() {
  local root="$1"
  local platform="$2"
  local user_id="$3"
  local identity_key="$4"
  local actor_workspace="${5:-}"
  local permissions_file

  permissions_file="$(permissions_file_for_root "$root")"
  [ -f "$permissions_file" ] || return 0

  awk -F'|' \
    -v platform="$platform" \
    -v user_id="$user_id" \
    -v identity_key="$identity_key" \
    -v actor_workspace="$actor_workspace" '
    function trim(s) {
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      return s
    }
    NR < 3 || $0 !~ /^\|/ { next }
    {
      workspace = trim($3)
      row_platform = trim($4)
      row_user_id = trim($5)
      row_identity_key = trim($8)
      role = trim($10)
      if (workspace == "Workspace" || workspace == "---" || workspace == "") {
        next
      }
      if (identity_key != "") {
        actor_match = (row_identity_key != "" &&
          row_identity_key == identity_key &&
          (row_platform == "" || platform == "" || row_platform == platform) &&
          (row_user_id == "" || user_id == "" || row_user_id == user_id))
      } else {
        actor_match = (row_platform == platform && row_user_id == user_id)
      }
      if (actor_match && (actor_workspace == "" || actor_workspace == workspace) && role != "") {
        print role
      }
    }
  ' "$permissions_file" | sed '/^$/d' | sort -u
}

permissions_unique_or_empty() {
  local label="$1"
  local values="$2"
  local required="${3:-0}"
  local count

  count="$(printf '%s\n' "$values" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
  case "$count" in
    0)
      [ "$required" -eq 0 ] && return 0
      die "$label is not uniquely mapped in workspace/admin/permissions.md"
      ;;
    1)
      printf '%s\n' "$values" | sed '/^$/d' | head -n 1
      ;;
    *)
      die "$label maps to multiple values in workspace/admin/permissions.md"
      ;;
  esac
}

permissions_actor_role_or_default() {
  local root="$1"
  local platform="$2"
  local user_id="$3"
  local identity_key="$4"
  local actor_workspace="$5"
  local default_role="$6"
  local roles
  local role

  roles="$(permissions_actor_roles "$root" "$platform" "$user_id" "$identity_key" "$actor_workspace")"
  role="$(permissions_unique_or_empty "actor role" "$roles" 0)"
  if [ -n "$role" ]; then
    printf '%s\n' "$role"
  else
    printf '%s\n' "$default_role"
  fi
}

permissions_group_authorized() {
  local root="$1"
  local platform="$2"
  local user_id="$3"
  local chat_id="$4"
  local identity_key="$5"
  local group_slug="$6"
  local groups

  [ -n "$group_slug" ] || return 0
  [ -n "$chat_id" ] || return 1
  groups="$(permissions_groups_for_actor_chat "$root" "$platform" "$user_id" "$chat_id" "$identity_key")"
  printf '%s\n' "$groups" | grep -Fxq "$group_slug"
}
