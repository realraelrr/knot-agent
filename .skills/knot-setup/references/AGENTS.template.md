# Knot Agent Workspace

Codex sessions for Knot start from this directory, except IM-triggered sessions
that are launched from the active workspace prepared by the IM glue layer.

## Layout

```text
components/   source repos and reusable code
runtime/      IM gateway configs, run scripts, logs, sockets, local secrets
workspace/    user files, knowledge, drafts, deliverables, task state
```

Use `workspace/` for agent work. Do not put temporary plans, generated files,
downloads, or outputs in the repository root.

Important workspace paths:

```text
workspace/knowledge/             approved knowledge mirror and local state
workspace/users/<user_slug>/     active user workspaces
workspace/groups/<group_slug>/   explicit shared group workspaces
workspace/groups/<group_slug>/work/<user_slug>/
                                  group actor lanes for drafts and task state
workspace/conversations/         IM source and audit metadata
workspace/admin/                 permissions and knowledge feedback
workspace/.state/tasks/          root-scoped recoverable task state
```

## Workflow

Use `knot-workflow` before Knot tasks that involve knowledge, IM, attachments,
generated files, deliverables, or multi-step delivery. Pure Q&A and small local
edits can run directly.

When task state is needed, use `bin/knot-planning.sh` so the plan lands under
the scope-aware task root. Root/operator tasks use
`workspace/.state/tasks/<task_id>/`. IM-triggered direct chats use
`workspace/users/<user_slug>/.state/tasks/<task_id>/`. IM-triggered group chats
use `workspace/groups/<group_slug>/work/<user_slug>/.state/tasks/<task_id>/`.

Treat `.state` as temporary: deliver user-visible results, promote durable
facts through the approved knowledge flow, and keep virtualenvs, caches, and
large intermediates out of it.

## Active Workspaces

For IM-triggered work, `bin/knot-workspace.sh` resolves the actor user,
optional source group, and conversation metadata, then prints source-safe
exports:

```text
KNOT_ACTIVE_WORKSPACE
KNOT_SCOPE
KNOT_SCOPE_WORKSPACE
KNOT_ACTOR_WORKSPACE
KNOT_USER_WORKSPACE
KNOT_GROUP_WORKSPACE
KNOT_CONVERSATION_DIR
```

The gateway should launch Codex from `KNOT_ACTIVE_WORKSPACE`.

- Direct chats use `KNOT_SCOPE=direct`; active, scope, and actor workspace all
  point to `workspace/users/<user_slug>`.
- Authorized group chats use `KNOT_SCOPE=group`; active and scope workspace
  point to `workspace/groups/<group_slug>`, while `KNOT_ACTOR_WORKSPACE` points
  to `workspace/groups/<group_slug>/work/<user_slug>`.

In group scope, read the current group workspace as shared context. Put drafts,
task state, and process files in `KNOT_ACTOR_WORKSPACE`; final group-facing
deliverables go to the current group `deliverables/` directory through the
delivery helper. The actor lane is an agent protocol, not OS-level isolation.

`workspace/conversations/<platform>/chat_<hash>/` is source and audit metadata
only. It is never a Codex cwd, work directory, deliverables directory, or task
state root.

## Authorization

`workspace/admin/permissions.md` is the source of truth for identity, roles, and
authorization. The IM glue layer and `bin/knot-workspace.sh` handle normal
workspace routing.

Read the permissions file before actions that modify system files, modify
durable knowledge, edit admin files, access another user's workspace, access a
group workspace, or send files outside the current direct user or authorized
current group deliverables.

## Knowledge

Shared durable knowledge is approved from the configured GitHub knowledge repo:
`main` is the authoritative approved ref, and `workspace/knowledge/vault/` is
the default local mirror. Knot should read only the approved mirror or a pinned
approved commit, never a proposal branch.

Use `bin/knot-knowledge.sh` for status, approved sync, member proposals,
admin review, and backup checks. Only identities with explicit `Role=admin` in
`workspace/admin/permissions.md` may approve durable knowledge; `operator` does
not imply knowledge approval. Members may create proposal branches, fork PRs, or
patch bundles only.

Keep conversion sidecars and knowledge ingest decoupled. Treat feedback as a
signal, not verified fact. Material knowledge changes require admin approval, a
visible diff, GitHub server-side branch protection, and a
`workspace/admin/knowledge-feedback.md` row with status and execution.

## Delivery

Final user-facing files go under the active direct user or current authorized
group `deliverables/` directory. Generation is not delivery.

Use `bin/knot-deliver.sh` to copy generated artifacts into the correct
deliverables directory. Use `bin/knot-attachment.sh` to validate an
existing deliverable and print the `cc-connect-attachments` block.

When sending a local file or image through IM, use:

````text
```cc-connect-attachments
image: $KNOT_ROOT/workspace/users/<user_slug>/deliverables/example.png
file: $KNOT_ROOT/workspace/groups/<group_slug>/deliverables/example.pdf
```
````
