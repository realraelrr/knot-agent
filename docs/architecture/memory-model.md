# Knot Memory Model

Status: design spec. Direct-chat memory pack generation and validated patch
apply are implemented; restricted block filtering, wiki promotion, and group
workspace migration are not yet implemented.

## Goal

Knot should behave like a durable enterprise digital worker across IM
platforms. The same business actor should carry the same working memory across
direct chats. In group chats, the agent should combine the actor's working
memory with the current group's collaborative working memory.

Knot remains a thin glue layer: Codex does the reasoning and summarization;
Knot defines paths, read/write boundaries, lifecycle rules, and delivery/audit
contracts.

## Reference Basis

This design is adapted from Hermes Agent and OpenClaw, with Knot-specific
enterprise workspace boundaries:

- Hermes uses small curated memory files, injects them as a frozen
  session-start snapshot, and keeps session search separate from memory.
- Hermes stores full sessions in SQLite/FTS for search. Knot does not copy this
  layer because Codex session history is already the transcript source of
  truth.
- Hermes group sessions can isolate per-user context. Knot extends that idea by
  making group memory readable to the group but writable only through
  actor-owned shards.
- OpenClaw keeps user-facing memory as Markdown files and treats indexes/plugins
  as retrieval aids, not as the authoring source of truth.
- OpenClaw separates compact long-term memory, daily/working notes, memory wiki,
  and pre-compaction flushes. Knot maps these to enterprise knowledge, working
  memory, and Codex transcript boundaries.

Sources:

- [Hermes persistent memory](https://hermes-agent.nousresearch.com/docs/user-guide/features/memory/)
- [Hermes sessions](https://hermes-agent.nousresearch.com/docs/user-guide/sessions)
- [Hermes memory manager source](https://github.com/NousResearch/hermes-agent/blob/main/agent/memory_manager.py)
- [OpenClaw memory](https://github.com/openclaw/openclaw/blob/main/docs/concepts/memory.md)

## Non-Goals

- Do not build a new agent runtime, planner, vector store, or policy engine.
- Do not introduce SQLite, FTS, vector storage, or a second transcript database
  into Knot for this design.
- Do not treat complete Codex transcripts as long-term memory.
- Do not store enterprise facts in user or group working memory.
- Do not make group memory a shared write target.

## Memory Layers

| Layer | Source of Truth | Purpose | Lifecycle |
|---|---|---|---|
| Enterprise knowledge | `workspace/knowledge/vault/` | Stable business facts, SOPs, policies, reference knowledge | Durable, reviewed, provenance-backed |
| Working memory | `workspace/users/<user>/memory/` and `workspace/groups/<group>/memory/users/<user>.md` | Active responsibilities, in-flight tasks, recent decisions, follow-ups, temporary constraints | Curated, expires or promotes |
| Session transcript | Codex session history plus compact `workspace/conversations/` metadata | Raw conversation continuity and audit evidence | Codex-owned transcript outside Knot memory |

Enterprise knowledge is the bottom memory layer. It is maintained through the
existing LLM Wiki flow and admin review. Working memory may reference wiki
pages, but must not duplicate durable knowledge.

`workspace/conversations/` stores compact source/audit metadata only. Full
Codex transcripts stay in Codex session history and are not copied into Knot
memory.

## Workspace Semantics

### Required Migration

This design intentionally changes the current group-chat rule. Today
group-triggered Codex sessions still start from the actor user workspace and
receive optional group context. The target design makes the group workspace the
active workspace for group chats because the task, deliverables, and
collaborative working memory belong to the group.

Before implementation, update the same rule in:

- `bin/knot-workspace.sh`
- the cc-connect workspace resolver
- `AGENTS.md`
- `knot-workflow`
- delivery/default write documentation and tests

Until that migration lands, the current implementation remains user-workspace
active for group-triggered sessions.

### Hard Safety Requirements

Implementation must fail closed when actor identity, group membership, or target
workspace cannot be resolved to exactly one authorized scope. In that case, Knot
must not load working memory, must not apply memory patches, and must emit a
compact audit event.

If group membership is not authorized, the pack builder must not generate a
group-scoped memory pack. It may generate only a denied audit event and a
minimal user-facing failure signal for the caller.

Normal Codex memory patches must not modify `profile.md`. Profile files are
read-only runtime context unless a separate admin/system-maintained profile
update flow explicitly authorizes the change.

Memory patches must include the expected base hash of the target file. The
helper must deny the patch if the current file hash differs from the expected
base hash.

Patch application must be atomic: apply to a temporary file in the same
directory, flush the temporary file, and rename it over the target only after
all validation passes. A failed apply must leave the original memory file
unchanged.

Patch validation must check more than target paths. The helper must reject path
traversal, absolute paths, symlinks, non-memory targets, raw transcript blocks,
secrets-looking additions, copied source-document blocks, unauthorized removal
or weakening of restricted markers, and group-scoped patches that copy
actor-private or direct-only memory into group-readable shards.

Semantic leakage is handled by reducing what reaches the group context, not by
asking the patch validator to understand every possible paraphrase. The pack
builder must exclude restricted user-memory blocks from group-scoped packs. The
validator then rejects direct copying of excluded blocks, transcript-like dumps,
restricted-marker weakening, and patches that claim restricted content in a
group-readable shard.

Cross-platform memory sharing must come from
`workspace/admin/permissions.md` identity mapping. Do not merge users by display
name, nickname, phone number guess, or chat-local labels. `Chat ID` identifies
source/group context; it is not actor identity.

When an `Identity Key` is present, it is the primary cross-platform actor key
and must map to exactly one workspace. If `Platform + Platform User ID` also
appears in the permissions table, it must map to the same workspace and must not
be ambiguous. If no `Identity Key` is present, `Platform + Platform User ID`
must map to exactly one workspace.

### Direct Chat

- `KNOT_ACTIVE_WORKSPACE` is `workspace/users/<user>/`.
- Read memory from `workspace/users/<user>/memory/`.
- Write memory patches only to `workspace/users/<user>/memory/`.
- Deliver files to `workspace/users/<user>/deliverables/`.

### Group Chat

- `KNOT_ACTIVE_WORKSPACE` is `workspace/groups/<group>/`.
- Read memory from:
  - `workspace/users/<actor>/memory/`
  - `workspace/groups/<group>/memory/users/*.md`
  - optional read-only group profile
  - enterprise wiki pointers, with selected pages only when required
- Write group working memory only to
  `workspace/groups/<group>/memory/users/<actor>.md`.
- Do not write actor user memory from the group-scoped patch. If a group task
  reveals an actor-level follow-up, emit a user-memory proposal that must be
  applied later through a user-scoped helper.
- Deliver files to `workspace/groups/<group>/deliverables/` by default.

Group memory is readable by authorized group participants but writable only by
the actor's own group memory shard. This avoids concurrent writes and keeps
responsibility traceable.

## Directory Contract

```text
workspace/
  knowledge/
    raw/
    processed/
    vault/                         # LLM Wiki durable knowledge
  users/
    <user_slug>/
      memory/
        profile.md                 # stable role/preferences relevant to work
        active.md                  # current responsibilities and tasks
        followups.md               # dated follow-up items
      inbox/
      work/
      deliverables/
  groups/
    <group_slug>/
      memory/
        profile.md                 # optional read-only group purpose/context
        users/
          <user_slug>.md           # actor-authored group working memory shard
      inbox/
      work/
      deliverables/
  conversations/
    <platform>/chat_<hash>/         # source metadata and compact audit events
```

The exact number of memory files may start smaller than this contract, but new
files must stay inside the same ownership model. `profile.md` is admin/system
maintained read-only context; it is not a working-memory patch target.

## Read/Write Matrix

| Context | Read User Memory | Read Group Memory | Read Wiki | Write User Memory | Write Group Memory | Write Wiki |
|---|---|---|---|---|---|---|
| Direct chat | actor only | no | pointers by default; pages on demand | actor only | no | feedback only |
| Group chat | actor only | current group shards and read-only profile | pointers by default; pages on demand | proposal only; no direct group-scope write | actor shard only | feedback only |
| Admin knowledge update | as task requires | as task requires | pages as task requires | no default | no default | reviewed wiki flow |

Writing wiki content still requires the existing knowledge feedback, visible
diff, and admin approval path. Memory helpers may create a feedback row but
must not bypass the wiki ingest/review contract.

## Runtime Flow

Before Codex starts, the IM glue layer resolves identity and chat context
through Knot helpers and writes `.knot/memory-pack.md` in the active workspace.
The pack is read-only input for Codex, can be overwritten on every message, and
is never a memory source of truth, deliverable, task record, or audit
transcript.

Codex uses memory through the `knot-memory` skill. The skill owns agent-side
behavior, while Knot helpers own deterministic checks, pack generation, file
permissions, and audit events. Do not duplicate the memory protocol in
`knot-workflow`; that skill should only route memory-sensitive tasks to
`knot-memory`.

The pack contains:

- active actor and group identity
- links or short excerpts from actor working memory
- group memory shards allowed in the current context
- wiki index pointers by default, with selected wiki excerpts only when relevant
- the write targets Codex may propose updates for

When a group-scoped pack includes actor user-memory excerpts, treat it as
ephemeral runtime input:

- create it with owner-only permissions such as `0600`
- clean it up after the Codex launch/session wrapper exits when the runtime can
  do so
- never preserve it as a debug artifact with memory excerpts
- if debugging needs a retained file, keep only source paths, hashes, selected
  target paths, and event IDs, not memory content

New `.knot/` runtime files and new memory files or shards must also be created
with owner-only permissions. Do not rely on a permissive process umask.

During execution, Codex reads the pack and works in `KNOT_ACTIVE_WORKSPACE`.
Codex should only propose memory updates in `.knot/memory-patch.md`; only the
deterministic helper applies validated memory changes.

After Codex finishes, the implemented direct-chat helper validates and applies
patches to actor user memory. The future group-scoped helper will extend the
same rule set:

- direct chat may patch only actor user memory
- group chat may patch only the actor's group shard
- actor user-memory updates discovered in group chat become a separate
  user-memory proposal, not a group-scoped patch target
- wiki changes become knowledge feedback, not direct wiki writes
- restricted markers are preserved

The patch format should be minimal and line-oriented:

```text
target: workspace/users/<user>/memory/active.md
base_sha256: <sha256 of target before Codex read it>

--- a/workspace/users/<user>/memory/active.md
+++ b/workspace/users/<user>/memory/active.md
@@
 ...
```

Do not design a custom memory DSL. `.knot/memory-patch.md` is temporary working
output and can be overwritten, ignored, or denied.

## Restricted Entries

Knot is an enterprise office agent, so working memory is shared for work unless
explicitly marked otherwise.

Use restricted entries only when a user explicitly says a memory should not be
used outside direct chat or a specific scope. Restricted markers apply to every
bullet inside a restricted begin/end block. The deterministic helper, not Codex,
is responsible for parsing these blocks and filtering them by scope. Restricted
entries are not loaded into group memory packs unless the current group is
explicitly listed.

```markdown
<!-- knot:restricted begin direct-only -->
- 2026-05-26: Example direct-only working note.
<!-- knot:restricted end -->

<!-- knot:restricted begin groups=finance -->
- 2026-05-26: Example finance-only working note.
<!-- knot:restricted end -->
```

## Size Budget

Memory stays useful by staying small. Exceeding the budget requires summarizing
or pruning existing memory; it must not trigger a new database, index service,
or vector store.

| File or Pack | Target Budget |
|---|---:|
| `workspace/users/<user>/memory/profile.md` | 100 lines |
| `workspace/users/<user>/memory/active.md` | 120 lines |
| `workspace/users/<user>/memory/followups.md` | 120 lines |
| `workspace/groups/<group>/memory/profile.md` | 80 lines |
| `workspace/groups/<group>/memory/users/<user>.md` | 120 lines |
| `.knot/memory-pack.md` | 300 lines |

When a file exceeds its budget, the helper should warn. Compaction may be
performed by Codex as a proposed patch, then applied by the same deterministic
patch helper.

## Memory Content Rules

Allowed content:

- active task ownership
- recent decisions that affect current work
- follow-up items
- temporary constraints
- user role or working preferences relevant to office execution
- links to wiki pages or deliverables

Disallowed content:

- copied source documents
- stable enterprise facts that belong in the wiki
- raw chat transcripts
- secrets or credentials
- other users' workspace files
- unreviewed external claims presented as durable knowledge

## Audit Boundary

Knot audits deterministic boundary actions, not every memory sentence.

Audit events should cover:

- memory pack generated
- memory patch applied
- memory patch denied
- knowledge feedback created from a memory promotion request

Audit rows stay compact and should not include raw memory content.

## Minimal Implementation Shape

The design requires only small glue helpers:

- resolve identity and workspace
- build memory pack from allowed files
- validate and apply memory patch
- route durable knowledge changes to feedback
- record compact audit events

It does not require a database, background indexer, semantic search service, or
new task record system.

## Implementation Order

Build the smallest useful slice first:

1. Direct-chat memory.
2. Deterministic memory-pack generation.
3. Patch validator with `base_sha256` and atomic apply.
4. Group workspace plus actor-owned group memory shard.
5. Restricted begin/end blocks.
6. Wiki feedback and memory promotion.

Do not start with vector storage, FTS, agent memory DB, or a broader policy
engine.

## Acceptance Criteria

- Unresolved or ambiguously mapped actors receive no working memory and cannot
  write memory.
- Unauthorized group membership produces no group-scoped memory pack and records
  a compact denied audit event.
- Normal Codex memory patches cannot modify `profile.md`.
- Memory patches include an expected base hash and are denied on conflict.
- Memory patch apply is atomic and failed apply leaves the original memory file
  unchanged.
- Newly created `.knot/` runtime files and memory files use owner-only
  permissions.
- Patch validation rejects path traversal, symlinks, absolute paths,
  non-memory targets, transcript blocks, secrets-looking additions, copied
  source-document blocks, unauthorized restricted-marker changes, and
  group-scoped leakage of actor-private or direct-only memory.
- Restricted entries are parsed and filtered by deterministic begin/end blocks.
- The same user mapped across multiple IM platforms reads the same user working
  memory.
- Direct chat writes only user working memory and user deliverables.
- Group chat runs from the group workspace, delivers to group deliverables, and
  reads actor user memory plus all current group memory shards.
- Group chat writes only the actor's group memory shard. Actor user-memory
  updates discovered in group chat are proposed separately and applied only by a
  user-scoped helper.
- Group memory has no shared working-memory write target.
- Working memory can link to enterprise wiki pages but does not duplicate wiki
  knowledge.
- Stable facts are promoted through the existing knowledge feedback and wiki
  review flow.
- No SQLite, FTS, vector backend, or new persistent service is required.
