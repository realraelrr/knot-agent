---
name: working-style
description: Use when a Knot task benefits from a specific human collaborator's work style, communication preferences, repeated corrections, or stable personal workflow cues.
---

# Knot Working Style

## Boundary

The working style is a small self-evolving Markdown file for one
human work partner. It helps Codex adapt collaboration style across platforms.

It is not enterprise knowledge, task state, a workflow library, a transcript
store, or an external provider integration:

- Stable business facts and SOPs go to `llm-wiki`.
- In-flight task planning goes to `planning-with-files`.
- Reusable operational flows become workflow skill or SOP candidates.
- Raw transcripts, secrets, source documents, and large copied excerpts never
  belong in `style.md`.

## Runtime Contract

- Source of truth:
  `workspace/users/<user_slug>/style.md`.
- Runtime snapshot:
  direct scope: `workspace/users/<user_slug>/.knot/style-pack.md`;
  group scope: `workspace/groups/<group_slug>/work/<user_slug>/.knot/style-pack.md`.
- Patch proposal:
  `workspace/users/<user_slug>/.knot/style.patch`.
- Audit target:
  `workspace/conversations/<platform>/chat_<hash>/events.jsonl`.

The deterministic helpers own identity resolution, path checks, base-hash
validation, schema linting, atomic apply, file permissions, content scanning,
and audit events. Do not bypass them by editing `style.md` manually.

## Agent Usage

If `.knot/style-pack.md` exists in the current direct workspace
or group actor lane, read it before work where collaboration style matters.

If the pack is missing and the runtime context is available, generate it:

```bash
bash "$KNOT_ROOT/bin/knot-working-style-pack.sh" pack \
  --root "$KNOT_ROOT" \
  --platform "$KNOT_PLATFORM" \
  --chat-id "$KNOT_CHAT_ID" \
  --user-id "$KNOT_PLATFORM_USER_ID" \
  --identity-key "$KNOT_IDENTITY_KEY" \
  --actor-user "$KNOT_ACTOR_USER" \
  --scope "$KNOT_SCOPE" \
  --active-workspace "$KNOT_ACTIVE_WORKSPACE" \
  --user-workspace "$KNOT_USER_WORKSPACE" \
  --actor-workspace "$KNOT_ACTOR_WORKSPACE" \
  --conversation-dir "$KNOT_CONVERSATION_DIR"
```

If the helper denies the pack, continue only when the request can be handled
without collaborator-specific context. Do not read `style.md` directly.

## Style Contents

Only record concise, durable collaboration cues:

- Communication style: brevity/detail preference, language, format, directness.
- Work habits: review style, preferred evidence, delivery expectations.
- Daily task flows: repeated personal entry points or recurring requests.
- Explicit corrections: "next time", "I prefer", "do not", "use this style".

Keep the complete style file under 1600 characters. Prefer replacing or merging
old bullets over appending forever.

When `style.md` uses structured frontmatter, only `version`, `updated`, and
`reviewed` are valid keys. Body sections are limited to `Communication`,
`Evidence And Review`, `Delivery`, `Recurring Workflows`, and `Avoid`, with at
most five bullets per section. Do not add enterprise facts, task notes, SOPs, or
raw history.

Run `bin/knot-working-style-lint.sh lint` for schema, length, and
safety checks. `style.md` above 1200 characters should be compacted by patch
proposal only; apply still goes through the normal direct-scope helper and its
validation.
Do not create persistent semantic conflict state for the style file.

## Self-Evolution Updates

Codex may proactively propose a style patch when:

- the user explicitly states a preference;
- the user corrects the agent's behavior;
- a stable personal collaboration pattern repeats in the current session;
- a complex task reveals a durable personal work preference.

Draft only `.knot/style.patch`, targeting only
`workspace/users/<user_slug>/style.md`, with the current
`base_sha256` from the pack:

```text
target: workspace/users/<user_slug>/style.md
base_sha256: <sha256 from style-pack.md>

--- a/workspace/users/<user_slug>/style.md
+++ b/workspace/users/<user_slug>/style.md
@@
 ...
```

Apply it only through:

```bash
bash "$KNOT_ROOT/bin/knot-working-style-apply.sh" apply \
  --root "$KNOT_ROOT" \
  --patch "$KNOT_ACTIVE_WORKSPACE/.knot/style.patch" \
  --platform "$KNOT_PLATFORM" \
  --chat-id "$KNOT_CHAT_ID" \
  --user-id "$KNOT_PLATFORM_USER_ID" \
  --identity-key "$KNOT_IDENTITY_KEY" \
  --actor-user "$KNOT_ACTOR_USER" \
  --scope "$KNOT_SCOPE" \
  --active-workspace "$KNOT_ACTIVE_WORKSPACE" \
  --user-workspace "$KNOT_USER_WORKSPACE" \
  --actor-workspace "$KNOT_ACTOR_WORKSPACE" \
  --conversation-dir "$KNOT_CONVERSATION_DIR"
```

Do not claim `style.md` changed unless the helper succeeds. In group scope,
the style pack is read-only and apply must be denied; do not silently write
personal working style updates from a group chat.

Workflow or SOP improvements must stay separate: propose a visible diff for
human review, and never silently modify core skills from an IM session.

## User-Facing Replies

Normal replies should not mention helper names, local paths, session internals,
patch files, base hashes, or audit events. If `style.md` was updated, say it
plainly, for example: `已记录你的协作偏好。`
