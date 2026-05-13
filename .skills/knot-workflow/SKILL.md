---
name: knot-workflow
description: Use when a Knot workspace task involves knowledge ingestion, wiki updates, IM-agent work, attachments, generated files, deliverables, or multi-step execution.
---

# Knot Workflow

Use this skill to route Knot tasks. Keep the individual skills independent:
Codex coordinates them; the skills do not depend on each other.

## First Decision

Classify the request before acting:

- **Knowledge source**: a document, folder, note, URL, or attachment should become reusable knowledge.
- **Knowledge query**: the user asks what the organization knows or what a source says.
- **Execution task**: the user wants analysis, drafting, PPT, HTML, file generation, research, automation, or operations work.
- **IM delivery**: the user wants a local file or image sent back through chat.
- **Medium or large task**: the task needs planning, confirmation, review,
  recovery, multiple steps, or cross-file work.

## Permission Check

Do not check permissions for every harmless IM request. Consult
`workspace/admin/permissions.md` only before modifying system files, modifying
durable knowledge, editing the permissions table, accessing another session, or
sending files outside the user's own session.

If a permission check is required and the user has no matching row, explain that
the action requires authorization and ask them to contact an admin.

- `operator`: system config, code, `AGENTS.md`, skills, runtime, and IM gateway.
- `admin`: durable knowledge, permissions, and knowledge feedback.
- `member`: own session workspace, session-generated files, approved knowledge
  reading, and feedback.

Only `operator` and `admin` may edit `workspace/admin/permissions.md`. The
permissions file is an operating contract for Codex, not a security sandbox.
When matching a user, prefer `Session Key` when present, then
`Platform + Chat ID + User ID`, then platform-specific fallback ids.

## Routing

- IM session setup: use `bootstrap/knot-session.sh` before storing uploads,
  drafts, deliverables, or task state for an IM-triggered request.
- Raw document to knowledge: use `docling-skill` when conversion helps, write
  intermediates under `workspace/knowledge/processed/`, then use
  `wiki-ingest` for durable knowledge.
- Direct knowledge ingest: use `wiki-ingest` when the source is already clean
  text or Markdown. Do not force a docling step.
- Knowledge query: use `wiki-query` first. If evidence is missing or stale,
  say so and, when allowed, propose a feedback or update path.
- Wiki maintenance: use obsidian-wiki skills such as `wiki-status`,
  `wiki-lint`, `wiki-update`, or `wiki-digest` only when the task calls for
  them.
- Presentation deliverable: use `guizang-ppt-skill`; write local/global final
  outputs under `workspace/deliverables/` and IM-triggered outputs under the
  session `deliverables/` directory.
- Simple execution: if no specialized skill or recoverable task state is
  needed, do the work directly and place drafts, inputs, and outputs in the
  matching `workspace/` location.
- Medium or large execution: follow `AGENTS.md` execution discipline.
- IM file/image delivery: use `bootstrap/knot-attachment.sh` to validate the
  file boundary and print the cc-connect attachment block. Do not answer with
  only a local path when the user asked to receive the file in IM.
- Knowledge feedback from members: append a row to
  `workspace/admin/knowledge-feedback.md`; admins decide whether to update
  durable knowledge.

## Storage Rules

- User inputs go under `workspace/inbox/` unless they are already in place.
- Approved long-term sources go under `workspace/knowledge/raw/`.
- Extracted sidecars and OCR outputs go under `workspace/knowledge/processed/`.
- Final user-facing files go under `workspace/deliverables/`.
- Drafts and reusable working assets go under `workspace/work/`.
- IM-triggered uploads, drafts, deliverables, and task state go under
  `workspace/sessions/<platform>/<chat_id>/<user_id>/`; create it with
  `bootstrap/knot-session.sh`.
- Use filesystem-safe path segments for IM ids. Preserve original ids in task
  notes or feedback rows when folder names are normalized.
- Do not put temporary work in the Knot root.

## Evidence Priority

- Prefer local knowledge and user-provided sources first.
- Use external web sources when the user asks, the task depends on current
  facts, local knowledge is missing, stale, or contradictory, or higher-priority
  instructions require external verification.
- Clearly distinguish local knowledge from external evidence.
- Do not write external claims into durable knowledge without admin approval or
  a visible diff.

## Backup Boundary

Daily rollback backup is handled by Codex app automation, not by ad hoc workflow
steps. The automation should call `bootstrap/knot-backup.sh`. If asked to
verify backup health, inspect `workspace/admin/backup-policy.md` and the
current git remote before claiming backup is active.

## Boundaries

- The wiki is memory and reference material, not the boundary of what Codex can
  do.
- Do not turn Knot into a static pipeline. Choose the shortest reliable path
  for the request.
- Keep conversion and wiki ingest decoupled.
- Treat feedback as a signal, not verified fact.
- Require human approval or a visible diff before material knowledge changes.
