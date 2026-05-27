# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

planning_root="$TMP_PARENT/planning-root"
mkdir -p "$planning_root/workspace/admin"
cat > "$planning_root/workspace/admin/permissions.md" <<'EOF'
| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| Direct User | direct-user | feishu | ou/direct |  | oc/direct | feishu:user:direct | Direct User | member | session | smoke |
| Direct User | direct-user | feishu | ou/direct | planning-group | oc/group | feishu:user:direct | Direct User | member | session | smoke |
EOF

planning_active_symlink_root="$TMP_PARENT/planning-active-symlink-root"
planning_active_symlink_sink="$TMP_PARENT/planning-active-symlink-sink.txt"
mkdir -p "$planning_active_symlink_root/workspace/users/direct-user/.state/tasks"
printf '%s\n' 'outside active pointer sentinel' > "$planning_active_symlink_sink"
ln -s "$planning_active_symlink_sink" "$planning_active_symlink_root/workspace/users/direct-user/.state/tasks/.active_task"
if bash "$ROOT/bin/knot-planning.sh" init \
  --root "$planning_active_symlink_root" \
  --scope direct \
  --actor-user direct-user \
  --task-id escaped-init \
  --now 2026-01-01T00:00:00Z >/dev/null 2>&1; then
  fail "planning init wrote active task through symlink"
elif grep -Fxq 'outside active pointer sentinel' "$planning_active_symlink_sink" &&
  [ ! -e "$planning_active_symlink_root/workspace/users/direct-user/.state/tasks/escaped-init" ]; then
  ok "planning init rejects symlinked active task pointer"
else
  fail "planning init modified outside active pointer or created task on symlink denial"
fi

if direct_task="$(bash "$ROOT/bin/knot-planning.sh" init \
  --root "$planning_root" \
  --scope direct \
  --actor-user direct-user \
  --task-id task-direct \
  --now 2026-01-01T00:00:00Z)" &&
  [ "$direct_task" = "$(absolute_path "$planning_root/workspace/users/direct-user/.state/tasks/task-direct")" ] &&
  [ -f "$direct_task/task_plan.md" ] &&
  jq -e '.status == "active" and .scope == "direct" and .actor_user == "direct-user"' "$direct_task/task.meta.json" >/dev/null; then
  ok "planning helper initializes direct scope task state"
else
  fail "planning helper did not initialize direct scope task state"
fi

if group_task="$(bash "$ROOT/bin/knot-planning.sh" init \
  --root "$planning_root" \
  --scope group \
  --actor-user direct-user \
  --group-slug planning-group \
  --task-id task-group \
  --now 2026-01-01T00:00:00Z)" &&
  [ "$group_task" = "$(absolute_path "$planning_root/workspace/groups/planning-group/work/direct-user/.state/tasks/task-group")" ] &&
  jq -e '.status == "active" and .scope == "group"' "$group_task/task.meta.json" >/dev/null; then
  ok "planning helper initializes group actor-lane task state"
else
  fail "planning helper did not initialize group actor-lane task state"
fi

if root_task="$(bash "$ROOT/bin/knot-planning.sh" init \
  --root "$planning_root" \
  --scope root \
  --task-id task-root \
  --now 2026-01-01T00:00:00Z)" &&
  [ "$root_task" = "$(absolute_path "$planning_root/workspace/.state/tasks/task-root")" ] &&
  jq -e '.status == "active" and .scope == "root"' "$root_task/task.meta.json" >/dev/null; then
  ok "planning helper initializes root scope task state"
else
  fail "planning helper did not initialize root scope task state"
fi

if resolved_task="$(KNOT_SCOPE=direct KNOT_ACTOR_USER=direct-user KNOT_USER_WORKSPACE="$planning_root/workspace/users/direct-user" \
  bash "$ROOT/bin/knot-planning.sh" resolve --root "$planning_root")" &&
  [ "$resolved_task" = "$direct_task" ]; then
  ok "planning helper resolves active direct task"
else
  fail "planning helper did not resolve active direct task"
fi

if PLAN_ID="../../admin" KNOT_SCOPE=direct KNOT_ACTOR_USER=direct-user \
  bash "$ROOT/bin/knot-planning.sh" resolve --root "$planning_root" >/dev/null 2>&1; then
  fail "planning helper allowed traversal PLAN_ID"
else
  ok "planning helper rejects traversal PLAN_ID"
fi

symlink_source="$planning_root/symlink-source"
symlink_task="$planning_root/workspace/users/direct-user/.state/tasks/task-link"
mkdir -p "$symlink_source"
cp "$direct_task/task_plan.md" "$symlink_source/task_plan.md"
jq '.status = "closed" | .closed_at = "2026-01-01T00:00:00Z"' "$direct_task/task.meta.json" > "$symlink_source/task.meta.json"
ln -s "$symlink_source" "$symlink_task"
if bash "$ROOT/bin/knot-planning.sh" cleanup delete --apply \
  --root "$planning_root" \
  --scope direct \
  --actor-user direct-user \
  --now 2026-01-10T00:00:00Z >/dev/null 2>&1; then
  fail "planning cleanup allowed symlinked task deletion"
else
  ok "planning cleanup rejects symlinked task deletion"
fi
rm -f "$symlink_task"

if bash "$ROOT/bin/knot-planning.sh" close \
  --root "$planning_root" \
  --scope direct \
  --actor-user direct-user \
  --task-id task-direct \
  --now 2026-01-01T00:00:00Z >/dev/null &&
  jq -e '.status == "closed" and .closed_at == "2026-01-01T00:00:00Z"' "$direct_task/task.meta.json" >/dev/null &&
  [ ! -f "$planning_root/workspace/users/direct-user/.state/tasks/.active_task" ]; then
  ok "planning helper closes direct task and clears active pointer"
else
  fail "planning helper did not close direct task"
fi

if delete_dry_run="$(bash "$ROOT/bin/knot-planning.sh" cleanup delete --dry-run \
  --root "$planning_root" \
  --scope direct \
  --actor-user direct-user \
  --now 2026-01-10T00:00:00Z)" &&
  printf '%s\n' "$delete_dry_run" | grep -Fq "delete task-direct" &&
  [ -d "$direct_task" ]; then
  ok "planning cleanup dry-run reports closed delete candidate"
else
  fail "planning cleanup did not report closed delete candidate"
fi

if delete_output="$(bash "$ROOT/bin/knot-planning.sh" cleanup delete --apply \
  --root "$planning_root" \
  --scope direct \
  --actor-user direct-user \
  --now 2026-01-10T00:00:00Z)" &&
  printf '%s\n' "$delete_output" | grep -Fq "deleted: task-direct" &&
  [ ! -e "$direct_task" ]; then
  ok "planning cleanup deletes closed task after retention window"
else
  fail "planning cleanup did not delete closed task after retention window"
fi

stale_task="$(bash "$ROOT/bin/knot-planning.sh" init \
  --root "$planning_root" \
  --scope direct \
  --actor-user direct-user \
  --task-id task-stale \
  --now 2026-01-01T00:00:00Z)"
bash "$ROOT/bin/knot-planning.sh" init \
  --root "$planning_root" \
  --scope direct \
  --actor-user direct-user \
  --task-id task-current \
  --now 2026-01-10T00:00:00Z >/dev/null
if stale_output="$(bash "$ROOT/bin/knot-planning.sh" cleanup scan \
  --root "$planning_root" \
  --scope direct \
  --actor-user direct-user \
  --now 2026-01-10T00:00:00Z)" &&
  printf '%s\n' "$stale_output" | grep -Fq "stale task-stale" &&
  ! printf '%s\n' "$stale_output" | grep -Fq "stale task-current" &&
  [ -d "$stale_task" ]; then
  ok "planning cleanup reports stale task without deleting it"
else
  fail "planning cleanup did not report stale task without deleting it"
fi

if bash "$ROOT/bin/knot-planning.sh" init \
  --root "$planning_root" \
  --scope direct \
  --actor-user "../escape" \
  --task-id bad-task >/dev/null 2>&1; then
  fail "planning helper allowed traversal actor slug"
else
  ok "planning helper rejects traversal actor slug"
fi
