# Knot Agent Workspace

Codex sessions for Knot start from this directory.

## Layout

```text
components/   source repos and reusable code
runtime/      IM gateway configs, run scripts, logs, sockets, local secrets
workspace/    user files, knowledge, drafts, deliverables, task state
```

Use `workspace/` for agent work:

```text
workspace/inbox/                 user-supplied inputs
workspace/knowledge/raw/         approved long-term sources
workspace/knowledge/processed/   sidecars, OCR, extracted intermediates
workspace/knowledge/vault/       Obsidian vault
workspace/work/                  drafts and reusable working assets
workspace/deliverables/          final files for users
workspace/admin/                 permissions and knowledge feedback
workspace/sessions/              IM-scoped user workspaces
workspace/.state/tasks/          recoverable task/session state
```

Do not put temporary plans, generated files, downloads, or outputs in the root.

## Execution Discipline

- Small tasks: answer or execute directly when the request is clear, low-risk,
  and reversible. Verify before claiming completion.
- Medium tasks: use `planning-with-files`; write the plan under task state, get
  human confirmation, execute, review the result, then deliver with verification.
- Large tasks: follow the medium-task process and use an independent subagent
  review before delivery.

Classify as medium when the task changes durable knowledge, creates meaningful
deliverables, touches multiple files, affects shared configuration, or needs
more than a few steps. Classify as large when it crosses system boundaries,
changes operating rules, affects multiple users, or has high recovery cost.

Use this task state shape:

```text
workspace/.state/tasks/<task_id>/
  task_plan.md
  findings.md
  progress.md
  files/
```

For IM-triggered medium or large work, use the session-local state directory
instead:

```text
workspace/sessions/<platform>/<chat_id>/<user_id>/.state/tasks/<task_id>/
```

Use task ids like:

```text
YYYYMMDD-HHMMSS-channel-short-topic
```

## Workflow Routing

Use `knot-workflow` before Knot tasks that involve knowledge, IM, attachments,
generated files, or multi-step delivery. Let it choose the next skill or tool;
do not duplicate detailed workflow rules here.

## Permissions

Do not check permissions for every harmless IM request. Read
`workspace/admin/permissions.md` only before actions that modify system files,
modify durable knowledge, edit the permissions table, access another user's
session files, or send files outside the user's own session. Reading approved
shared knowledge does not require a permissions check.

If a permission check is required and the user has no matching row, explain that
the action requires authorization and ask them to contact an admin.

Roles:

- `operator`: may change system config, code, `AGENTS.md`, skills, runtime
  config, and IM gateway setup.
- `admin`: may ingest, edit, delete, approve, and organize knowledge; may
  maintain `workspace/admin/permissions.md` and
  `workspace/admin/knowledge-feedback.md`.
- `member`: may ask questions, use agent capabilities in their own session
  workspace, receive files generated in that session, read approved knowledge,
  and append knowledge feedback.

Only `operator` and `admin` may edit `workspace/admin/permissions.md`. This
permissions file is an agent operating contract, not a security sandbox.
When matching a user, prefer `Session Key` when present, then
`Platform + Chat ID + User ID`, then platform-specific fallback ids.

## Session Isolation

For IM-triggered work, store user uploads, drafts, deliverables, and task state
under:

```text
workspace/sessions/<platform>/<chat_id>/<user_id>/
  inbox/
  work/
  deliverables/
  .state/tasks/
```

Use filesystem-safe path segments for IM ids. Preserve the original `chat_id`
and `user_id` in task notes or feedback rows when they differ from folder names.

Shared durable knowledge remains under `workspace/knowledge/`. Non-admin users
should not inspect or reuse other users' session files unless explicitly
authorized by `workspace/admin/permissions.md`.

## Backup Automation

Key durable data must be committed and pushed once per day by a Codex app
automation. See `workspace/admin/backup-policy.md`.

Back up `AGENTS.md`, `.skills/knot-setup/`, `.skills/knot-workflow/`,
`workspace/knowledge/`, and `workspace/admin/`. Do not back up `runtime/`,
`components/`, logs, sockets, locks, local secrets, or caches. Use a
customer-controlled git remote named `backup`; if no git repo or safe `backup`
remote exists, report setup required instead of pretending a backup happened.

## Knowledge Work

- Use `docling-skill` for document conversion.
- Use `obsidian-wiki` skills for ingest, query, status, lint, and update.
- Use `guizang-ppt-skill` when creating magazine-style or e-ink HTML/PPT
  presentation deliverables.
- Keep conversion and wiki ingest decoupled.
- Treat feedback as a signal, not verified fact.
- Require human approval or a visible diff before material knowledge changes.
- Prefer local knowledge sources first. Use external web sources only when the
  user asks, the task depends on current facts, or local knowledge is missing,
  stale, or contradictory, unless higher-priority instructions require external
  verification. Clearly distinguish local knowledge from external evidence.

## IM Attachments

Text replies are delivered by `cc-connect`.

When sending a local file or image through IM, use:

````text
```cc-connect-attachments
image: $KNOT_ROOT/workspace/sessions/<platform>/<chat_id>/<user_id>/deliverables/example.png
file: $KNOT_ROOT/workspace/sessions/<platform>/<chat_id>/<user_id>/deliverables/example.pdf
```
````

Do not answer with only a local path when the user asked to send the file.
