# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

governance_root="$TMP_PARENT/governance-root"
mkdir -p "$governance_root/workspace/admin" \
  "$governance_root/workspace/users/admin-user/deliverables" \
  "$governance_root/workspace/users/member-user/deliverables" \
  "$governance_root/workspace/groups/product-room/deliverables"

cat > "$governance_root/workspace/admin/permissions.md" <<'EOF'
| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| Admin User | admin-user | feishu | ou/admin | product-room | oc/product | feishu:user:admin | Admin User | admin | knowledge | smoke |
| Member User | member-user | feishu | ou/member | product-room | oc/product | feishu:user:member | Member User | member | session | smoke |
EOF

admin_role="$(permissions_actor_role_or_default "$governance_root" feishu ou/admin feishu:user:admin admin-user member)"
member_role="$(permissions_actor_role_or_default "$governance_root" feishu ou/member feishu:user:member member-user member)"
admin_workspace="$(permissions_unique_or_empty "actor identity" "$(permissions_actor_workspaces "$governance_root" feishu ou/admin feishu:user:admin)" 1)"
member_group="$(permissions_unique_or_empty "group context" "$(permissions_groups_for_actor_chat "$governance_root" feishu ou/member oc/product feishu:user:member)" 1)"

if [ "$admin_role" = "admin" ] &&
  [ "$member_role" = "member" ] &&
  [ "$admin_workspace" = "admin-user" ] &&
  [ "$member_group" = "product-room" ] &&
  permissions_can_approve_knowledge "$governance_root" feishu ou/admin feishu:user:admin admin-user &&
  ! permissions_can_approve_knowledge "$governance_root" feishu ou/member feishu:user:member member-user &&
  permissions_can_apply_profile "$governance_root" feishu ou/member feishu:user:member member-user direct &&
  ! permissions_can_apply_profile "$governance_root" feishu ou/member feishu:user:member member-user group &&
  permissions_can_use_group "$governance_root" feishu ou/member oc/product feishu:user:member product-room; then
  ok "governance permissions predicates share one Role and Scope contract"
else
  fail "governance permissions predicates did not resolve expected roles and scopes"
fi

if workspace_output="$(bash "$ROOT/bin/knot-workspace.sh" \
  --root "$governance_root" \
  --platform feishu \
  --chat-id oc/product \
  --user-id ou/member \
  --identity-key feishu:user:member \
  --no-create)" &&
  printf '%s\n' "$workspace_output" | grep -Fq "KNOT_ACTOR_USER='member-user'" &&
  printf '%s\n' "$workspace_output" | grep -Fq "KNOT_SCOPE='group'" &&
  printf '%s\n' "$workspace_output" | grep -Fq "KNOT_GROUP_SLUG='product-room'"; then
  ok "knot-workspace uses shared permissions actor and group resolution"
else
  fail "knot-workspace did not use shared permissions actor and group resolution"
fi

if knowledge_status="$(bash "$ROOT/bin/knot-knowledge.sh" status \
  --root "$governance_root" \
  --platform feishu \
  --user-id ou/admin \
  --identity-key feishu:user:admin \
  --actor-user admin-user)" &&
  printf '%s\n' "$knowledge_status" | grep -Fxq "role=admin"; then
  ok "knot-knowledge uses shared permissions role resolution"
else
  fail "knot-knowledge did not report admin role from shared permissions"
fi

printf 'group deliverable\n' > "$governance_root/workspace/groups/product-room/deliverables/report.txt"
if bash "$ROOT/bin/knot-attachment.sh" \
  --root "$governance_root" \
  --platform feishu \
  --chat-id oc/product \
  --user-id ou/member \
  --identity-key feishu:user:member \
  --user-slug member-user \
  --group-slug product-room \
  --kind file \
  --path "$governance_root/workspace/groups/product-room/deliverables/report.txt" >/dev/null; then
  ok "delivery boundary accepts shared permissions-authorized group context"
else
  fail "delivery boundary rejected shared permissions-authorized group context"
fi
