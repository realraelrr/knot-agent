# Collaborator Profile

Status: implemented for direct user workspaces and read-only group-chat packs.

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

workspace/groups/<group_slug>/work/<user_slug>/
  .knot/
    collaborator-profile-pack.md
```

`collaboration/profile.md` is the only source of truth. It is created
owner-only (`0600`) by the pack helper when missing.

`.knot/collaborator-profile-pack.md` is a runtime snapshot. In direct scope it
lives under the user `.knot/` directory. In group scope it is a read-only
snapshot written under the group actor lane. It may be regenerated for every
session and is never a durable source.

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

Structured profiles may use only `version`, `updated`, and `reviewed`
frontmatter keys. Body sections are fixed to `Communication`,
`Evidence And Review`, `Delivery`, `Recurring Workflows`, and `Avoid`, with at
most five bullets per section. Profiles over 1200 characters should produce a
compact recommendation, but compaction is still only a patch proposal.
Lint stays structural: it does not infer or persist semantic conflict state.

## Runtime Flow

1. The IM glue layer resolves the actor and launches Codex from the actor user
   workspace for direct chats, or from the current group workspace for
   authorized group chats.
2. The pack helper validates identity, permissions, active workspace, symlinks,
   profile contents, size, and conversation audit target.
3. In direct scope, the helper creates or tightens `collaboration/profile.md`,
   writes `.knot/collaborator-profile-pack.md`, and returns success only after
   the audit event is recorded. In group scope, the helper reads the actor's
   user profile and writes a read-only pack to
   `workspace/groups/<group_slug>/work/<user_slug>/.knot/` without creating or
   modifying the user profile.
4. Codex may read the pack as frozen session-start context.
5. If the session reveals a stable collaborator cue, Codex drafts
   `.knot/collaborator-profile.patch` with `base_sha256`.
6. The apply helper is direct-scope only. It validates the patch, atomically
   replaces `collaboration/profile.md`, and rolls the file back if the success
   audit event cannot be recorded. Group-scope apply is denied.

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
- direct `KNOT_ACTIVE_WORKSPACE` must equal the actor user workspace;
- group `KNOT_ACTIVE_WORKSPACE` must equal the current authorized group
  workspace, with the pack written to `KNOT_ACTOR_WORKSPACE`;
- the profile target must be exactly
  `workspace/users/<user_slug>/collaboration/profile.md`;
- all new runtime/profile files are owner-only;
- patches must include a matching `base_sha256`;
- path traversal, absolute paths, symlinks, non-profile targets, malformed
  diffs, raw transcript blocks, source-document blocks, secrets-looking
  additions, invalid structured schema, and oversized output are denied;
- apply uses temporary output in the same directory and atomic replacement;
- successful pack generation and patch application require compact audit
  events; denied actions write audit events when the audit target is valid.

This keeps the product surface small: Codex decides whether a collaborator cue
is useful, while Knot deterministically decides whether the update is allowed.
