# Security Model

Knot is a local-first Codex harness. Its default permissions are an operating
contract enforced by deterministic helper scripts where possible; they are not a
process sandbox, container boundary, or operating-system access-control layer.

## Trust Boundaries

- **Codex execution:** Codex performs the task inside the workspace selected by
  the IM glue layer or by the operator.
- **Codex session history:** Codex session history is the transcript source of
  truth for user and model messages.
- **Knot helpers:** `bin/knot-workspace.sh`, `bin/knot-deliver.sh`,
  `bin/knot-attachment.sh`, and `bin/knot-audit.sh` provide
  deterministic workspace routing, delivery validation, and compact boundary
  event records that follow `docs/schemas/audit-event.schema.json`.
- **Workspace data:** `workspace/users/<user_slug>/` is the default private
  working area for one actor. `workspace/groups/<group_slug>/` is for explicit
  shared group assets. `workspace/conversations/` is source and audit metadata,
  not a work or delivery directory.
- **Runtime data:** `runtime/` contains IM configs, logs, sockets, and local
  secrets. It is operator-managed infrastructure, not user deliverable storage.
- **Shared knowledge:** `workspace/knowledge/` contains approved durable
  knowledge. Material changes require admin approval and an audit row.

## Boundary Classes

| Class | Boundary | Enforced by | Meaning |
|---|---|---|---|
| Hard guardrail | Workspace routing, deliverable attachment paths, symlink rejection, component lockfile format, static active-workspace config rejection | Deterministic Knot helpers and doctor checks | These checks must pass before the related helper action succeeds. |
| Soft protocol | User-facing reply style, knowledge-change approval records, use of `.state/`, durable knowledge promotion, admin review expectations | Agent instructions, templates, and human review | These rules guide Codex and operators, but they are not process isolation. |
| Out of scope | OS tenant isolation, enterprise DLP, platform credential authorization, network egress control, complete sensitive-data classification | External infrastructure and enterprise controls | These require controls outside the default Knot scaffold. |

## What Knot Prevents

In the default local setup, Knot's deterministic helpers reject:

- delivery from another user's workspace;
- delivery from another group's workspace unless the current actor and chat are
  authorized for that group;
- attachment blocks that point outside the current user or authorized group
  `deliverables/` directory;
- attachments sourced from `workspace/conversations/`;
- symlink escapes from current workspaces and deliverables directories;
- static `KNOT_ACTIVE_WORKSPACE` runtime configuration;
- component lockfile rows that point outside the pinned component layout.

## What Knot Does Not Prevent

Knot does not, by itself:

- stop a local process from reading files that the operating-system user can
  read;
- isolate users with separate Unix accounts, containers, VMs, or filesystem
  jails;
- guarantee that an LLM will never mention internal paths or system details;
- validate live IM credentials or platform-side authorization without live
  smoke testing;
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
- explicit shared work uses `workspace/groups/<group_slug>/`;
- recoverable agent working state can live under `.state/` when needed;
- conversation metadata and boundary event records live under
  `workspace/conversations/<platform>/chat_<hash>/`;
- approved durable knowledge lives under `workspace/knowledge/`.

This model is appropriate for trusted operators, demos, pilots, and internal
teams where the local OS account is already trusted. It is not equivalent to OS
or tenant isolation.

## IM Attachment Boundary

IM outbound files must be delivered from the active user's `deliverables/`
directory or the authorized current group's `deliverables/` directory. Use
`bin/knot-deliver.sh` to copy generated artifacts into that boundary and
`bin/knot-attachment.sh` to emit the `cc-connect-attachments` block.

Files from `runtime/`, `workspace/conversations/`, another user's workspace, or
another group's workspace are not valid outbound attachments in the default
helper contract.

## Admin And Operator Responsibilities

- Operators maintain code, runtime config, platform credentials, backup remotes,
  and release checks.
- Admins maintain `workspace/admin/permissions.md` and approve durable
  knowledge changes.
- Knowledge changes require a human-reviewable diff, approval status, execution
  evidence, and a row in `workspace/admin/knowledge-feedback.md`.
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
