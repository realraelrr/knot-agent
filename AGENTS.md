# Knot Agent Workspace

Codex sessions for Knot start from this directory, except IM-triggered sessions
that are launched from the active user workspace prepared by the IM glue layer.

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
workspace/knowledge/             approved shared knowledge
workspace/users/<user_slug>/     active user workspaces
workspace/groups/<group_slug>/   explicit shared group workspaces
workspace/conversations/         IM source and audit metadata
workspace/admin/                 permissions and knowledge feedback
workspace/.state/tasks/          root-scoped recoverable task state
```

## Workflow

Use `knot-workflow` before Knot tasks that involve knowledge, IM, attachments,
generated files, deliverables, or multi-step delivery. Pure Q&A and small local
edits can run directly.

When task state is needed, write it under `workspace/.state/tasks/<task_id>/`.
For IM-triggered work, use
`workspace/users/<user_slug>/.state/tasks/<task_id>/`.

Treat `.state` as temporary: deliver user-visible results, promote durable
facts to `workspace/knowledge/` or admin audit records, and keep virtualenvs,
caches, and large intermediates out of it.

## Active Workspaces

For IM-triggered work, `bin/knot-workspace.sh` resolves the actor user,
optional source group, and conversation metadata, then prints source-safe
exports:

```text
KNOT_ACTIVE_WORKSPACE
KNOT_USER_WORKSPACE
KNOT_GROUP_WORKSPACE
KNOT_CONVERSATION_DIR
```

The gateway should launch Codex from `KNOT_ACTIVE_WORKSPACE`. Write to the
active user workspace by default. Write to `KNOT_GROUP_WORKSPACE` only for
explicit shared group assets.

`workspace/conversations/<platform>/chat_<hash>/` is source and audit metadata
only. It is never a Codex cwd, work directory, deliverables directory, or task
state root.

## Authorization

`workspace/admin/permissions.md` is the source of truth for identity, roles, and
authorization. The IM glue layer and `bin/knot-workspace.sh` handle normal
workspace routing.

Read the permissions file before actions that modify system files, modify
durable knowledge, edit admin files, access another user's workspace, access a
group workspace, or send files outside the active user or explicit current
group deliverables.

## Knowledge

Shared durable knowledge lives under `workspace/knowledge/`. Keep conversion
sidecars and wiki ingest decoupled. Treat feedback as a signal, not verified
fact. Material knowledge changes require admin approval, a visible diff, and a
`workspace/admin/knowledge-feedback.md` row with status and execution.

## Delivery

Final user-facing files go under the active user or explicit current group
`deliverables/` directory. Generation is not delivery.

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
