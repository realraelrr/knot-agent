# shellcheck shell=bash

[ "${KNOT_DELIVERY_SH_LOADED:-0}" -eq 1 ] && return 0
KNOT_DELIVERY_SH_LOADED=1

knot_delivery_message_for_reason_code() {
  local command="$1"
  local reason_code="$2"
  local group_slug="$3"
  local resource_path="$4"
  local conversation_message="cannot deliver files from workspace/conversations"
  local outside_message="source file belongs outside the current user or group workspace"
  local denied_message="delivery denied"

  if [ "$command" = "attachment" ]; then
    conversation_message="attachments cannot be sent from workspace/conversations"
    outside_message="attachment must be inside the current user or group deliverables directory"
    denied_message="attachment denied"
  fi

  case "$reason_code" in
    unauthorized_group)
      printf 'group workspace is not authorized for this actor/context: %s\n' "$group_slug"
      ;;
    conversation_source_denied)
      printf '%s\n' "$conversation_message"
      ;;
    outside_deliverables)
      printf '%s\n' "$outside_message"
      ;;
    invalid_resource)
      printf 'file not found: %s\n' "$resource_path"
      ;;
    *)
      printf '%s\n' "$denied_message"
      ;;
  esac
}

knot_delivery_deny() {
  local command="$1"
  local reason_code="$2"
  local resource_kind="$3"
  local resource_path="$4"
  local group_slug="$5"
  local message

  message="$(knot_delivery_message_for_reason_code "$command" "$reason_code" "$group_slug" "$resource_path")"
  knot_audit_deny_delivery "$reason_code" "$resource_kind" "$resource_path" "$message"
}

knot_delivery_deny_with_message() {
  local reason_code="$1"
  local resource_kind="$2"
  local resource_path="$3"
  local message="$4"

  knot_audit_deny_delivery "$reason_code" "$resource_kind" "$resource_path" "$message"
}

knot_delivery_deny_group_access() {
  local command="$1"
  local group_slug="$2"
  local message

  message="$(knot_delivery_message_for_reason_code "$command" unauthorized_group "$group_slug" "")"
  knot_audit_deny_group_access "$message"
}
