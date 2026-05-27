# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

if grep -Eq '^(message_for_reason_code|deny_delivery|deny_delivery_with_message|deny_group_access)\(\)' \
  "$ROOT/bin/knot-deliver.sh" \
  "$ROOT/bin/knot-attachment.sh"; then
  fail "delivery CLIs still define duplicated deny/message helpers"
else
  ok "delivery CLIs share deny/message helpers from library"
fi

if grep -REq --include='*.sh' \
  'EXPLICIT_CONTEXT|EXPLICIT_IDENTITY_KEY|EXPLICIT_GROUP_SLUG|clear_implicit_identity_key' \
  "$ROOT/bin" \
  "$ROOT/lib/knot"; then
  fail "context parser explicit-clear state still has residual references"
else
  ok "context parser has no explicit-clear state residuals"
fi

if grep -REq --include='*.sh' \
  'parse_knot_context_arg' \
  "$ROOT/bin" \
  "$ROOT/lib/knot"; then
  fail "context parser name does not make field-only behavior explicit"
else
  ok "context parser name makes field-only behavior explicit"
fi
