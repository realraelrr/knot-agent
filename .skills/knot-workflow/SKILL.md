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

Use the lightest execution weight that fits:

- **quick**: answer or make a small local edit directly; no task state.
- **durable**: create a deliverable, durable knowledge change, IM artifact, or
  multi-step result; use task state only when it helps recovery or handoff.
- **risky**: change code behavior, config, permissions, runtime, public
  interfaces, schemas, deployment, or cross-system behavior; plan the work and
  confirm boundary-changing choices.

## User-Facing Replies And Internal Protocol

Default to the user-visible result. Keep helper names, session internals,
`.state`, local paths, and verification detail out of normal replies unless the
request is admin/ops work, the user asks for debugging, the detail is needed for
a decision, or file delivery requires a location or attachment block.

## Permission Check

Normal workspace routing is handled before launch by `bootstrap/knot-workspace.sh`.
For role and identity rules, read `workspace/admin/permissions.md` only when the
task crosses an authorization boundary.

## Routing

- IM workspace setup: the IM glue layer should call
  `bootstrap/knot-workspace.sh` with parsed platform/user/group metadata before
  launching Codex. Codex should run from `KNOT_ACTIVE_WORKSPACE`, which must be
  the actor's `workspace/users/<user_slug>` directory.
- Raw document to knowledge: use an available conversion skill when conversion
  helps, write intermediates under `workspace/knowledge/processed/`, then use an
  available knowledge-ingest skill for durable knowledge.
- Direct knowledge ingest: use an available knowledge-ingest skill when the
  source is already clean text or Markdown. Do not force a conversion step.
- Knowledge query: use an available knowledge-query skill first. If evidence is
  missing or stale, say so and, when allowed, propose a feedback or update path.
- Wiki maintenance: use available wiki maintenance skills only when the task
  calls for them.
- User-facing deliverables: use the available spreadsheet, document,
  presentation, PDF, web deck, or Markdown-rendering skill that matches the
  requested output. Use conversion skills instead when the goal is extraction,
  sidecars, or knowledge ingest.
- General execution: use the execution weights above; create workspace files
  only when the task needs them.
- IM file/image delivery: generation is not delivery. For generated or local
  artifacts, use `bootstrap/knot-deliver.sh` to copy the file into the current
  user deliverables directory, or into the current group deliverables directory
  only when the output is explicitly a shared group asset. Then delegate to
  `bootstrap/knot-attachment.sh` to validate the boundary and print the
  cc-connect attachment block. Do not answer with only a local path when the
  user asked to receive the file in IM.
- Knowledge feedback from members: append a row to
  `workspace/admin/knowledge-feedback.md`; admins decide whether to update
  durable knowledge.

## Storage Rules

- User inputs go under the active user workspace `inbox/` unless they are
  already in place.
- Approved long-term sources go under `workspace/knowledge/raw/`.
- Extracted sidecars and OCR outputs go under `workspace/knowledge/processed/`.
- Final user-facing files go under the active user workspace `deliverables/`,
  or the current group `deliverables/` only for explicit shared group assets.
- Drafts and reusable working assets go under the active user workspace `work/`.
- IM-triggered uploads, drafts, deliverables, and task state go under the actor
  user's `workspace/users/<user_slug>/` workspace. For group chats, use
  `KNOT_GROUP_WORKSPACE` only for explicitly shared group assets.
- Conversation source and audit metadata goes under
  `workspace/conversations/<platform>/<chat_id>/`. Do not use conversation
  directories as a Codex cwd, work directory, deliverables directory, or task
  state root.
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

## Runtime Boundary

Before starting a selected IM gateway, run
`bootstrap/knot-runtime-check.sh --platform <name>`. It checks local files,
required `.env` values, `KNOT_ROOT`, writability, and basic platform config
matching only. It does not start the gateway, call `/whoami`, or verify live IM
authorization.

## Boundaries

- The wiki is memory and reference material, not the boundary of what Codex can
  do.
- Do not turn Knot into a static pipeline. Choose the shortest reliable path
  for the request.
- Keep conversion and wiki ingest decoupled.
- Treat feedback as a signal, not verified fact.
- Require human approval or a visible diff before material knowledge changes.
