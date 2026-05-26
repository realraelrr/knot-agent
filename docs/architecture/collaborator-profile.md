# Collaborator Profile

Status: implemented for direct user workspaces.

## Goal

Knot needs lightweight continuity for how a specific human collaborator prefers
to work with the agent. The collaborator profile provides that continuity
without turning Knot into a storage engine or agent runtime.

The design borrows only the useful local-file principles from Hermes-style
agents: bounded Markdown files, a frozen runtime snapshot at session start,
agent-proposed updates, deterministic validation, and separation between
persistent profile cues and raw session history.

## Non-Goals

- Do not store enterprise facts, SOPs, policies, or source-backed business
  knowledge here.
- Do not store task scratchpads, intermediate decisions, or handoff state here.
- Do not store reusable tool procedures or delivery standards here.
- Do not copy raw transcripts, source documents, secrets, or large excerpts.
- Do not introduce external storage providers or a second transcript database.

Use the existing routes instead:

| Need | Route |
|---|---|
| Stable enterprise knowledge | `llm-wiki` and knowledge review |
| Single-task planning and progress | `planning-with-files` |
| Reusable business workflow | workflow skill or SOP candidate |
| Human collaboration preference | collaborator profile |

## Directory Contract

```text
workspace/users/<user_slug>/
  collaboration/
    profile.md
  .knot/
    collaborator-profile-pack.md
    collaborator-profile.patch
```

`collaboration/profile.md` is the only source of truth. It is created
owner-only (`0600`) by the pack helper when missing.

`.knot/collaborator-profile-pack.md` is a runtime snapshot. It may be
regenerated for every session and is never a durable source.

`.knot/collaborator-profile.patch` is temporary agent output. It is applied only
through the deterministic helper.

## Profile Contents

The profile records only durable collaboration cues:

- Communication style: concise vs detailed, preferred language, output format,
  and whether the user wants direct challenge.
- Work habits: evidence standards, review style, delivery preferences.
- Daily task flows: repeated personal task entry points.
- Explicit corrections: "以后不要", "以后按", "我更喜欢", or equivalent stable
  instructions.

The full rendered profile must stay under 1600 characters. Updates should merge
or replace older bullets rather than append indefinitely.

## Runtime Flow

1. The IM glue layer resolves the actor and launches Codex from the actor user
   workspace.
2. The pack helper validates identity, permissions, active workspace, symlinks,
   profile contents, size, and conversation audit target.
3. The helper creates or tightens `collaboration/profile.md`, writes
   `.knot/collaborator-profile-pack.md`, and returns success only after the
   audit event is recorded.
4. Codex may read the pack as frozen session-start context.
5. If the session reveals a stable collaborator cue, Codex drafts
   `.knot/collaborator-profile.patch` with `base_sha256`.
6. The apply helper validates the patch, atomically replaces
   `collaboration/profile.md`, and rolls the file back if the success audit
   event cannot be recorded.

## Update Policy

Codex may proactively propose an update when the user explicitly states a
preference, corrects agent behavior, repeats a stable personal work pattern, or
a completed complex task reveals a durable collaboration preference.

The profile must not absorb general enterprise knowledge or task notes. When in
doubt, route the information to the appropriate knowledge, planning, or SOP
path instead of stretching the profile.

## Deterministic Boundaries

Helpers enforce the hard rules:

- actor identity must resolve uniquely from `workspace/admin/permissions.md`;
- `KNOT_ACTIVE_WORKSPACE` must equal the actor user workspace;
- the profile target must be exactly
  `workspace/users/<user_slug>/collaboration/profile.md`;
- all new runtime/profile files are owner-only;
- patches must include a matching `base_sha256`;
- path traversal, absolute paths, symlinks, non-profile targets, malformed
  diffs, raw transcript blocks, source-document blocks, secrets-looking
  additions, and oversized output are denied;
- apply uses temporary output in the same directory and atomic replacement;
- successful pack generation and patch application require compact audit
  events; denied actions write audit events when the audit target is valid.

This keeps the product surface small: Codex decides whether a collaborator cue
is useful, while Knot deterministically decides whether the update is allowed.
