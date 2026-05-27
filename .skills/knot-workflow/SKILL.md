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
- **Collaborator profile**: the task depends on the human collaborator's
  communication style, work habits, repeated corrections, or stable personal
  workflow cues; use `knot-collaborator-profile`.

Use the lightest execution weight that fits:

- **quick**: answer or make a small local edit directly; no task state.
- **durable**: create a deliverable, durable knowledge change, IM artifact, or
  multi-step result; use task state only when it helps recovery or handoff.
- **risky**: change code behavior, config, permissions, runtime, public
  interfaces, schemas, deployment, or cross-system behavior; plan the work and
  confirm boundary-changing choices.

## User-Facing Replies And Internal Protocol

Default to the user-visible result. Normal replies must not mention helper or
script names, local paths, workspace internals, session metadata, `.state`,
logs, verification commands, or attachment-block protocol details. For file
delivery, use brief text such as `已整理好文件并发送给你。`, `已生成并发送：<filename>`,
or `已生成并发送 3 个文件：A.pdf、B.xlsx、C.md。` Include internals only when the
user asks for debugging or implementation evidence.

## Permission Check

Normal workspace routing is handled before launch by `bin/knot-workspace.sh`.
For role and identity rules, read `workspace/admin/permissions.md` only when the
task crosses an authorization boundary.

## Routing

- IM workspace setup: the IM glue layer should call
  `bin/knot-workspace.sh` with parsed platform/user/group metadata before
  launching Codex. Codex should run from `KNOT_ACTIVE_WORKSPACE`: direct chats
  use the actor's `workspace/users/<user_slug>` directory; authorized group
  chats use the current `workspace/groups/<group_slug>` directory.
- Raw document to knowledge: use an available conversion skill when conversion
  helps, write intermediates under the active workspace, then use an available
  knowledge-ingest skill to produce a reviewable proposal. Durable knowledge is
  approved through the GitHub-backed knowledge repo, not by direct local writes.
- Direct knowledge ingest: use an available knowledge-ingest skill when the
  source is already clean text or Markdown. Do not force a conversion step.
- Knowledge query: use an available knowledge-query skill first. If evidence is
  missing or stale, say so and, when allowed, propose a feedback or update path.
- Wiki maintenance: use available wiki maintenance skills only when the task
  calls for them.
- Collaborator profile: use `knot-collaborator-profile` only for personal
  collaboration preferences and corrections. Enterprise facts belong in
  reusable knowledge, task progress belongs in task planning, and reusable
  operations belong in workflow skill or SOP candidates.
- User-facing deliverables: use the available spreadsheet, document,
  presentation, PDF, web deck, or Markdown-rendering skill that matches the
  requested output. Use conversion skills instead when the goal is extraction,
  sidecars, or knowledge ingest.
- General execution: use the execution weights above; create workspace files
  only when the task needs them.
- IM file/image delivery: generation is not delivery. For generated or local
  artifacts, use `bin/knot-deliver.sh` to copy the file into the current
  direct-user deliverables directory or, in group scope, the current group
  deliverables directory. Then delegate to `bin/knot-attachment.sh` to validate
  the boundary and print the cc-connect attachment block. Do not answer with
  only a local path when the user asked to receive the file in IM.
- Knowledge feedback from members: append a row to
  `workspace/admin/knowledge-feedback.md` and use `bin/knot-knowledge.sh propose`
  to create a proposal bundle or PR source. Durable changes need
  `Diff`, `Status`, and `Execution`; only explicit admins may run the approval
  path.

## Learning Routes

- Personal collaboration style, repeated corrections, and stable individual
  work preferences may update the collaborator profile through
  `knot-collaborator-profile`.
- Enterprise knowledge, policies, facts, and source-backed decisions go through
  `llm-wiki` and the GitHub-backed knowledge feedback/review path. Knot runtime
  should read only the approved main mirror or a pinned approved commit.
- Single-task progress, intermediate decisions, blockers, and handoff state go
  through `planning-with-files` when task tracking is needed. Use
  `bin/knot-planning.sh` so the task lands in the direct, group actor-lane, or
  root `.state/tasks/` lifecycle.
- Reusable business procedures and delivery standards become workflow skill or
  SOP candidates with a human-reviewable diff. Do not silently change core
  skills from an IM session.

## Storage Rules

- Direct-chat user inputs go under the active user workspace `inbox/` unless
  they are already in place.
- Group-chat drafts, task state, and process files go under
  `KNOT_ACTOR_WORKSPACE`, which is
  `workspace/groups/<group_slug>/work/<user_slug>`. The full current group
  workspace is readable shared context.
- Approved long-term knowledge lives in the configured GitHub knowledge repo;
  `workspace/knowledge/vault/` is the default local approved mirror.
- Extracted sidecars and OCR outputs stay separate from approved knowledge and
  should remain in the active workspace until they become reviewable proposals.
- Final user-facing files go under the active direct user's `deliverables/`, or
  the current authorized group `deliverables/` in group scope.
- Direct-chat drafts and reusable working assets go under the active user
  workspace `work/`; group-chat drafts use `KNOT_ACTOR_WORKSPACE`.
- Conversation source and audit metadata goes under
  `workspace/conversations/<platform>/chat_<hash>/`. Do not use conversation
  directories as a Codex cwd, work directory, deliverables directory, or task
  state root.
- Do not put temporary work in the Knot root.
- Treat `.state` as temporary: deliver user-facing results, promote durable
  facts through the approved knowledge flow, and keep virtualenvs, caches, and
  large intermediates out of it.

## Evidence Priority

- Prefer local knowledge and user-provided sources first.
- Use external web sources when the user asks, the task depends on current
  facts, local knowledge is missing, stale, or contradictory, or higher-priority
  instructions require external verification.
- Clearly distinguish local knowledge from external evidence.
- Do not write external claims into durable knowledge without admin approval and
  a knowledge-feedback row with diff, status, and execution. GitHub branch
  protection and CODEOWNERS review are the hard durable-knowledge boundary;
  local helpers are an audit and mistake-prevention layer.

## Backup Boundary

Daily rollback backup is handled by Codex app automation, not by ad hoc workflow
steps. The automation should call `bin/knot-backup.sh`. If asked to
verify backup health, inspect `workspace/admin/backup-policy.md` and the
current git remote before claiming backup is active.

## Runtime Boundary

Before starting a selected IM gateway, run
`bin/knot-runtime-check.sh --platform <name>`. It checks local files,
required `.env` values, `KNOT_ROOT`, writability, and basic platform config
matching only. It does not start the gateway, call `/whoami`, or verify live IM
authorization.

## Boundaries

- The wiki is durable knowledge and reference material, not the boundary of
  what Codex can do.
- Do not turn Knot into a static pipeline. Choose the shortest reliable path
  for the request.
- Keep conversion and wiki ingest decoupled.
- Treat feedback as a signal, not verified fact.
