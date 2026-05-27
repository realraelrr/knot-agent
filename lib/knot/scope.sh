# shellcheck shell=bash

[ "${KNOT_SCOPE_SH_LOADED:-0}" -eq 1 ] && return 0
KNOT_SCOPE_SH_LOADED=1

knot_scope_user_workspace() {
  local root="$1"
  local actor_user="$2"

  validate_slug "--actor-user" "$actor_user"
  printf '%s\n' "$root/workspace/users/$actor_user"
}

knot_scope_group_workspace() {
  local root="$1"
  local group_slug="$2"

  validate_slug "--group-slug" "$group_slug"
  printf '%s\n' "$root/workspace/groups/$group_slug"
}

knot_scope_actor_workspace() {
  local root="$1"
  local scope="$2"
  local actor_user="$3"
  local group_slug="${4:-}"

  case "$scope" in
    root)
      printf '%s\n' "$root/workspace"
      ;;
    direct)
      knot_scope_user_workspace "$root" "$actor_user"
      ;;
    group)
      validate_slug "--actor-user" "$actor_user"
      [ -n "$group_slug" ] || die "--group-slug or KNOT_GROUP_SLUG is required"
      validate_slug "--group-slug" "$group_slug"
      printf '%s\n' "$root/workspace/groups/$group_slug/work/$actor_user"
      ;;
    *)
      die "--scope must be root, direct, or group"
      ;;
  esac
}

knot_scope_task_root() {
  local root="$1"
  local scope="$2"
  local actor_user="${3:-}"
  local group_slug="${4:-}"

  case "$scope" in
    root)
      printf '%s\n' "$root/workspace/.state/tasks"
      ;;
    direct)
      printf '%s\n' "$(knot_scope_user_workspace "$root" "$actor_user")/.state/tasks"
      ;;
    group)
      printf '%s\n' "$(knot_scope_actor_workspace "$root" "$scope" "$actor_user" "$group_slug")/.state/tasks"
      ;;
    *)
      die "--scope must be root, direct, or group"
      ;;
  esac
}
