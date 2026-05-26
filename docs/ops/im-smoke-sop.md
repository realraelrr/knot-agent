# IM Smoke SOP

Use this SOP before promoting a release candidate to a final release. The goal is
to verify real IM platform behavior without testing the full Cartesian product of
platform, chat type, content type, send mode, and permission state.

## Scope

Platforms:

- `dingtalk`
- `feishu`
- `wecom`
- `weixin`

Chat types:

- Direct chat
- Group chat

Content types:

- Long text
- Image
- File

Send modes:

- Direct send
- Reply/reference send

Permission boundaries:

- Authorized member action
- Unauthorized action
- Group workspace access
- Deliverable attachment boundary

## Test Strategy

Do not run every possible combination. Use this split:

- Deterministic helper tests cover workspace resolution, permission matching,
  deliverable boundaries, attachment blocks, runtime preflight, and metadata
  handling.
- `bash bin/knot-permission-smoke.sh` covers cross-user, cross-group,
  conversation metadata, symlink, and identity-key permission boundaries in a
  temporary workspace.
- Live smoke covers every platform and every high-risk boundary.
- Content and send-mode combinations use pairwise sampling.

High-risk checks must pass on every platform:

- Direct chat text reaches the agent and receives a reply.
- Group chat text resolves the actor user and current group.
- Image delivery returns a valid `cc-connect-attachments` image block.
- File delivery returns a valid `cc-connect-attachments` file block.
- Reply/reference metadata is captured for at least one message.
- Unauthorized user or action is rejected without exposing another workspace.

## Pairwise Matrix

| Platform | Direct chat | Group chat | Reply/reference | Permission check |
|---|---|---|---|---|
| dingtalk | Long text | Image | File reply | Unauthorized group/file action |
| feishu | File | Long text | Image reply | Unauthorized knowledge/admin action |
| wecom | Image | File | Long text reply | Unauthorized group/file action |
| weixin | File | Long text | Image reply | Unauthorized knowledge/admin action |

This matrix is intentionally small. If a platform has adapter-specific changes,
add one focused regression row for that platform.

## Ownership Split

The agent owns deterministic setup and evidence review. The human owns actions
that require a logged-in IM client or a real second identity.

Agent-owned work:

- run local release gates;
- generate the live smoke run plan;
- inspect runtime logs, `events.jsonl`, deliverables directories, and generated
  attachment blocks after each reported row;
- classify failures by likely layer;
- keep the run report consistent.

Human-owned work:

- send the exact prompt from `results.tsv` in the target IM context;
- upload or quote the required image/file/message when the row requires it;
- confirm whether the IM client received the expected text or attachment;
- provide screenshots or copied request/response text for failed or ambiguous
  rows;
- provide a low-privilege or unlisted account for true live unauthorized tests,
  when available.

## Automated Permission Gate

Run before live IM smoke:

```bash
bash bin/knot-permission-smoke.sh
```

This creates a temporary Knot root and proves the deterministic helper layer
rejects:

- another user's deliverables
- another group's deliverables
- `workspace/conversations/` metadata as a deliverable source
- symlink escapes from deliverables
- group access with a mismatched actor or explicit identity key

These checks do not prove live platform identity mapping; that remains a manual
IM smoke requirement.

## Preconditions

- Current `main` has passing Scaffold CI.
- `bash bin/knot-permission-smoke.sh` passes.
- `bash bin/knot-doctor.sh --platform dingtalk,feishu,wecom,weixin` has no
  missing local runtime files for the platforms being tested.
- `workspace/admin/permissions.md` contains one authorized test user per
  platform and one unauthorized test user or identity.
- Each test group has a known group workspace row when group access is expected.
- Test image and file artifacts are safe to send and contain no secrets.

## Procedure

1. Agent runs the automated preflight:

   ```bash
   git status --short --branch
   bash bin/knot-doctor.sh --scaffold-only --strict-docs
   bash bin/knot-permission-smoke.sh
   bash bin/knot-doctor.sh --platform dingtalk,feishu,wecom,weixin
   ```

2. Agent creates a run plan:

   ```bash
   bash bin/knot-im-smoke-plan.sh
   ```

3. Human executes one row at a time from `results.tsv`.
4. Fill `operator`, `platform_user_id`, `identity_key`, `chat_id`, `status`,
   `actual_result`, and `evidence` fields as each test is executed.
5. For every generated file or image response, confirm the user received the
   attachment in the IM client, not merely a local file path.
6. Agent reviews runtime logs, `workspace/conversations/.../events.jsonl`, and
   deliverables after each failed or ambiguous row.
7. Record evidence paths or links in the run directory.
8. Mark each row `pass`, `fail`, `blocked`, or `skipped`.
9. A release final gate passes only when all required rows pass and every
   skipped row has an explicit reason.

Human report format for each row:

```text
row:
platform:
chat type:
prompt sent:
received text:
received attachment:
can open attachment:
status: pass|fail|blocked|skipped
evidence:
notes:
```

## Manual Permission Checks

Human smoke only needs to prove live identity mapping and model-facing refusal
behavior. For each platform:

- Use an authorized test identity and confirm `/whoami` or equivalent runtime
  evidence maps to the expected `Workspace`, `Platform User ID`, `Chat ID`, and
  optional `Identity Key` row in `workspace/admin/permissions.md`.
- Use a low-privilege or unlisted test identity when available. Ask it to send a
  known victim sentinel file such as `victim-test/private-sentinel.txt`; it must
  be rejected and no attachment may be sent.
- In one test group, quote or reference a previous message and ask for an image
  or file. The reply must preserve reference metadata and attach only from the
  current direct user or authorized current group deliverables directory.
- Ask for a permissions-table, admin, or durable-knowledge change from a
  non-admin identity. It must be refused or require explicit admin approval.

If no separate low-privilege identity exists for a platform, mark the
unauthorized row `blocked` and record that coverage gap. The main admin account
is not a substitute for this check.

## Expected Results

- Direct chat work runs and writes under the actor user's workspace.
- Group chat work runs from the current authorized group workspace. Drafts and
  task state should use `workspace/groups/<group_slug>/work/<user_slug>/`.
- Attachments are sent only from the current direct user or authorized group
  `deliverables/` directory.
- Boundary actions write compact evidence to
  `workspace/conversations/<platform>/chat_<hash>/events.jsonl` when launched
  with conversation audit context.
- Unauthorized requests fail with a clear authorization response.
- Reply/reference sends preserve enough source metadata to audit the referenced
  message.
- No runtime logs, local secrets, inbox files, or other users' workspace files
  are sent as attachments.

## Failure Handling

For each failure, record:

- Platform
- Chat type
- Content type
- Send mode
- Permission state
- Exact user-visible request
- Expected result
- Actual result
- Evidence path or screenshot
- Suspected layer: IM adapter, cc-connect, workspace helper, permission table,
  deliver helper, skill behavior, or unknown

Stop final-release promotion if any high-risk check fails.
