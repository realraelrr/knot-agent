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
- **Execution mode**: apply `AGENTS.md` `quick` / `durable` / `risky` rules.

## User-Facing Replies And Internal Protocol

Default to the user-visible result. Keep helper names, session internals,
`.state`, local paths, and verification detail out of normal replies unless the
request is admin/ops work, the user asks for debugging, the detail is needed for
a decision, or file delivery requires a location or attachment block.

## Permission Check

Apply the permissions contract in `AGENTS.md`; do not duplicate role or matching
rules here.

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
- Office Pack deliverables: use Office Pack skills when the user wants to
  create, edit, fill, format, or deliver office files or presentations:
  `office-xlsx` for XLSX/CSV spreadsheets, `office-pptx` for native PPTX,
  `web-ppt` for browser HTML decks, `office-docx` for DOCX, and `office-pdf`
  for polished PDFs or PDF forms. Use `docling-skill` instead when the goal is
  extraction, conversion sidecars, or knowledge ingest.
- Markdown-to-human deliverable: use `md-for-human` when Markdown source should
  remain the durable source of truth but the user needs a readable HTML site.
- General execution: follow `AGENTS.md` execution modes; create workspace files
  only when the task needs them.
- IM file/image delivery: generation is not delivery. For generated or local
  artifacts, use `bootstrap/knot-deliver.sh` to copy the file into the current
  session `deliverables/` directory, then delegate to
  `bootstrap/knot-attachment.sh` to validate the boundary and print the
  cc-connect attachment block. Do not answer with only a local path when the
  user asked to receive the file in IM.
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
