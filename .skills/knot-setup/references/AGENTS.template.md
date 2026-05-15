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

## Execution Modes

Choose the thinnest mode that can produce a reliable user result.

- `quick`: pure Q&A, lightweight analysis, or single-file low-risk text
  handling. Execute directly, follow core safety rules, and verify only what is
  necessary before claiming completion.
- `durable`: creates a deliverable, writes `.state`, or involves
  knowledge or IM work. Use a lightweight plan and delivery record when they
  help recovery or handoff.
- `risky`: changes code behavior, config, permissions, runtime,
  cross-system behavior, public interfaces, or long-running work. Plan, get
  confirmation when boundaries may change, verify the result, and use
  independent review when the risk justifies it.

Force `planning-with-files` only for high recovery cost, cross-system or
cross-repo work, public interface/config/permission/runtime changes, long
tasks, explicit user requests for planning, or unclear risk where continuing
would change a behavior boundary. Ordinary deliverables and small multi-step
tasks do not automatically require the heavy plan flow.

When task state is needed, use this shape:

```text
workspace/.state/tasks/<task_id>/
  task_plan.md
  findings.md
  progress.md
  files/
```

For IM-triggered durable or risky work, use the session-local state directory
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
do not duplicate detailed workflow rules here. Default user-facing replies
should describe the result, not the internal process; `knot-workflow` owns the
detailed reply and tool routing protocol.

## Thin Glue Helpers

Use deterministic helper scripts for high-frequency fixed work:

- `bootstrap/knot-session.sh`: create or resolve the current IM session
  workspace before storing uploads, drafts, deliverables, or task state.
- `bootstrap/knot-attachment.sh`: validate that an outbound file is inside the
  current session `deliverables/` directory and print the cc-connect attachment
  block.
- `bootstrap/knot-deliver.sh`: copy a generated or local artifact into the
  current session `deliverables/` directory, validate it, and print the
  cc-connect attachment block.
- `bootstrap/knot-backup.sh`: daily rollback backup entrypoint for Codex app
  automation.
- `bootstrap/knot-runtime-check.sh`: static preflight for selected IM runtime
  files, credentials, `KNOT_ROOT`, and basic platform config matching.

These scripts enforce deterministic filesystem, runtime, and backup boundaries
only. Codex still decides the task path, evidence strategy, knowledge
maintenance action, and whether human approval is required.

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

Only `operator` and `admin` may edit `workspace/admin/permissions.md`. These
permissions are an agent operating contract, not a complex sandbox or runtime
security boundary.
When matching a user, prefer `Session Key` when present, then
`Platform + Chat ID + User ID`.

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
Use `bootstrap/knot-session.sh` for this path creation instead of hand-rolling
session folders. The helper prints the actual normalized path, which may differ
from the conceptual `<chat_id>/<user_id>` shape shown here.

Shared durable knowledge remains under `workspace/knowledge/`. Non-admin users
should not inspect or reuse other users' session files unless explicitly
authorized by `workspace/admin/permissions.md`.

## Backup Automation

Key durable data must be committed and pushed once per day by a Codex app
automation. See `workspace/admin/backup-policy.md`.

Back up `AGENTS.md`, `bootstrap/`, `.skills/knot-setup/`,
`.skills/knot-workflow/`, `workspace/knowledge/`, and `workspace/admin/`.
Do not back up `runtime/`, `components/`, logs, sockets, locks, local secrets,
or caches. Use a customer-controlled git remote named `backup`; if no git repo
or safe `backup` remote exists, report setup required instead of pretending a
backup happened. The automation should call `bootstrap/knot-backup.sh`.

## Knowledge Work

- Use `docling-skill` for document conversion.
- Use `obsidian-wiki` skills for ingest, query, status, lint, and update.
- Use `web-ppt` when creating magazine-style or e-ink HTML/PPT
  presentation deliverables.
- Use the Office Pack skills for native office-file deliverables:
  `office-xlsx` for spreadsheets, `office-pptx` for PPTX, `office-docx` for
  DOCX, and `office-pdf` for polished PDFs.
- Route document work by intent: use `docling-skill` for extraction,
  conversion, sidecars, and knowledge ingestion; use Office Pack for creating,
  editing, filling, formatting, or delivering office files; use lightweight
  `doc` or `pdf` skills only for quick local inspection or simple edits that
  do not need durable sidecars or high-fidelity delivery.
- Keep conversion and wiki ingest decoupled.
- Treat feedback as a signal, not verified fact.
- Require human approval or a visible diff before material knowledge changes.
- Prefer local knowledge sources first. Use external web sources only when the
  user asks, the task depends on current facts, or local knowledge is missing,
  stale, or contradictory, unless higher-priority instructions require external
  verification. Clearly distinguish local knowledge from external evidence.

## IM Attachments

Text replies are delivered by `cc-connect`.

For IM-triggered image or file generation, generation is not delivery. The
artifact must be placed under the current session `deliverables/` directory,
validated, and returned as a `cc-connect-attachments` block. Prefer
`bootstrap/knot-deliver.sh` for this handoff. Do not claim the user received a
generated image, file, PPT, HTML, PDF, video, or archive unless the attachment
block was produced.

When sending a local file or image through IM, use:

````text
```cc-connect-attachments
image: $KNOT_ROOT/workspace/sessions/<platform>/<chat_id>/<user_id>/deliverables/example.png
file: $KNOT_ROOT/workspace/sessions/<platform>/<chat_id>/<user_id>/deliverables/example.pdf
```
````

Do not answer with only a local path when the user asked to send the file.
Prefer `bootstrap/knot-attachment.sh` to validate the file boundary and generate
the attachment block.
