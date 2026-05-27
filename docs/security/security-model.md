# Security Model

Knot is a local-first Codex harness. Its default permissions are an operating
contract enforced by deterministic helper scripts where possible; they are not a
process sandbox, container boundary, or operating-system access-control layer.

## Trust Boundaries

- **Codex execution:** Codex performs the task inside the workspace selected by
  the IM glue layer or by the operator. Direct chats launch from the actor user
  workspace; authorized group chats launch from the current group workspace.
- **Codex session history:** Codex session history is the transcript source of
  truth for user and model messages.
- **Knot helpers:** `bin/knot-workspace.sh`, `bin/knot-deliver.sh`,
  `bin/knot-attachment.sh`, `bin/knot-collaborator-profile-pack.sh`,
  `bin/knot-collaborator-profile-apply.sh`,
  `bin/knot-collaborator-profile-lint.sh`, `bin/knot-knowledge.sh`,
  `bin/knot-planning.sh`, and `bin/knot-audit.sh` provide deterministic
  workspace routing, delivery/profile validation, knowledge proposal checks,
  planning lifecycle checks, and compact boundary event records that follow
  `docs/schemas/audit-event.schema.json`.
- **Workspace data:** `workspace/users/<user_slug>/` is the direct-chat working
  area for one actor. `workspace/groups/<group_slug>/` is the active shared
  workspace for authorized group chats, with actor lanes under
  `workspace/groups/<group_slug>/work/<user_slug>/`. `workspace/conversations/`
  is source and audit metadata, not a work or delivery directory.
- **Runtime data:** `runtime/` contains IM configs, logs, sockets, and local
  secrets. It is operator-managed infrastructure, not user deliverable storage.
- **Shared knowledge:** the configured GitHub knowledge repo is the durable
  source. Its protected `main` ref is the approved knowledge boundary, and
  `workspace/knowledge/vault/` is the default local mirror. Material changes
  require explicit admin approval and review evidence.

## Boundary Classes

| Class | Boundary | Enforced by | Meaning |
|---|---|---|---|
| Hard guardrail | Workspace routing, identity ambiguity denial, deliverable attachment paths, symlink rejection, component lockfile format, static active-workspace config rejection, GitHub branch protection for the knowledge repo | Deterministic Knot helpers, doctor checks, and GitHub server-side rules | These checks must pass before the related helper action succeeds or an approved knowledge change can land. |
| Soft protocol | Group actor-lane writes, user-facing reply style, knowledge-change proposal records, use of `.state/`, durable knowledge promotion, admin review expectations | Agent instructions, templates, local helpers, and human review | These rules guide Codex and operators, but local helpers are not process isolation. |
| Out of scope | OS tenant isolation, enterprise DLP, platform credential authorization, network egress control, complete sensitive-data classification | External infrastructure and enterprise controls | These require controls outside the default Knot scaffold. |

## What Knot Prevents

In the default local setup, Knot's deterministic helpers reject:

- delivery from another user's workspace;
- delivery from another group's workspace;
- delivery from source paths outside the current direct user's `work/`,
  `inbox/`, or `deliverables/` directories, or outside the current group actor
  lane and group `deliverables/` directory in group scope;
- delivery from actor lane `.knot/` or `.state/` internal state;
- group-scope delivery back into a user workspace;
- attachment blocks that point outside the current direct user or authorized
  current group `deliverables/` directory;
- attachments sourced from `workspace/conversations/`;
- symlink escapes from current workspaces and deliverables directories;
- static `KNOT_ACTIVE_WORKSPACE` runtime configuration;
- component lockfile rows that point outside the pinned component layout;
- collaborator profile snapshots or patches containing marked transcript/source
  document blocks, secrets-looking assignments, or content beyond the bounded
  profile size;
- structured collaborator profiles with invalid frontmatter, invalid sections,
  or too many bullets;
- planning archive or expiration of active or current task-pointer plans;
- local knowledge proposal writes that target the approved mirror or are made
  with member credentials carrying GitHub tokens.

## What Knot Does Not Prevent

Knot does not, by itself:

- stop a local process from reading files that the operating-system user can
  read;
- isolate users with separate Unix accounts, containers, VMs, or filesystem
  jails;
- guarantee that an LLM will never mention internal paths or system details;
- validate live IM credentials or platform-side authorization without live
  smoke testing;
- make multiple GitHub identities secure when every session runs as the same
  operating-system user with access to the same keychain and files;
- classify all sensitive data in logs, prompts, uploaded files, or generated
  outputs;
- replace enterprise DLP, SIEM, EDR, MDM, secret vaults, or legal/compliance
  review.

## Local Secrets Policy

- Keep platform credentials and tokens in `runtime/*/.env` or the operator's
  chosen secret manager.
- Do not place secrets in `workspace/`, `components/`, `docs/`, training
  examples, generated deliverables, or committed templates.
- Do not set `KNOT_ACTIVE_WORKSPACE` in `.env`; the active workspace is resolved
  per message by the gateway/helper flow.
- Treat runtime logs as sensitive until reviewed. Do not attach logs through IM
  unless an operator explicitly approves the exact file and recipient.

## Workspace Isolation Model

The default workspace model is logical isolation inside one local checkout:

- user work defaults to `workspace/users/<user_slug>/`;
- authorized group-chat work launches from `workspace/groups/<group_slug>/`;
- group-chat drafts and task state should use
  `workspace/groups/<group_slug>/work/<user_slug>/`;
- recoverable agent working state should be created through
  `bin/knot-planning.sh` under the scope-aware `.state/tasks/<task_id>/` root;
- conversation metadata and boundary event records live under
  `workspace/conversations/<platform>/chat_<hash>/`;
- approved durable knowledge is read from the protected GitHub knowledge repo's
  approved ref, mirrored locally under `workspace/knowledge/vault/` by default.

This model is appropriate for trusted operators, demos, pilots, and internal
teams where the local OS account is already trusted. It is not equivalent to OS
or tenant isolation.

## IM Attachment Boundary

IM outbound files must be delivered from the active direct user's
`deliverables/` directory or, in group scope, the authorized current group's
`deliverables/` directory. Use
`bin/knot-deliver.sh` to copy generated artifacts into that boundary and
`bin/knot-attachment.sh` to emit the `cc-connect-attachments` block.

`bin/knot-deliver.sh` accepts source files only from the current direct user's
`work/`, `inbox/`, or `deliverables/` directories, or in group scope from the
current group actor lane excluding `.knot/` and `.state/`, or current group
`deliverables/` directory. Files from `runtime/`, `workspace/admin/`,
`workspace/conversations/`, repository metadata, another user's workspace,
another group's workspace, or arbitrary root paths are not valid outbound
sources in the default helper contract.

## Admin And Operator Responsibilities

- Operators maintain code, runtime config, platform credentials, backup remotes,
  and release checks.
- Admins maintain `workspace/admin/permissions.md` and approve durable
  knowledge changes. `operator` does not imply knowledge approval unless the
  identity also has explicit `Role=admin`.
- Knowledge changes require a human-reviewable diff, approval status, execution
  evidence, GitHub protected-branch enforcement, and a row in
  `workspace/admin/knowledge-feedback.md`.
- Member credentials must not have merge, approve, or `main` write permission
  on the knowledge repo.
- Live IM rollout requires platform smoke tests because local helper tests do
  not prove platform identity mapping.
- Permission-table changes must be reviewed as access-control changes, even
  though the table is a markdown operating contract.

## Enterprise Hardening Recommendations

For stricter enterprise environments, add controls outside the default scaffold:

- run separate customers or high-risk roles under separate OS users, containers,
  or VMs;
- mount workspaces with least-privilege filesystem permissions;
- store secrets in an enterprise vault and inject only scoped runtime values;
- centralize runtime logs with redaction, retention, and access review;
- enforce outbound network policy at the OS, proxy, or firewall layer;
- require human approval for destructive actions and external sends;
- export boundary event records and IM delivery events into the organization's
  audit system;
- run release gates, permission smoke, live IM smoke, and file validation before
  production rollout.
