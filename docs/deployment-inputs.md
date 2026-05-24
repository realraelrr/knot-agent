# Deployment Inputs

This checklist captures the minimum inputs needed to install Knot for a real
organization. It is not a business demo template and does not prescribe a use
case.

## Runtime Scope

- Target Knot root path:
- Target machine owner or operator:
- Enabled IM platforms:
- Platforms intentionally out of scope:
- Expected release or rollout date:

## Identities And Workspaces

For each enabled platform, collect:

- Authorized platform user IDs.
- Stable identity keys, when available.
- User slugs for `workspace/users/<user_slug>/`.
- Group chat IDs that should map to shared group workspaces.
- Group slugs for `workspace/groups/<group_slug>/`.
- Roles: `operator`, `admin`, or `member`.
- Low-privilege or unlisted test identity, if available.

The deployment is not ready for live permission smoke unless each claimed
platform has at least one known authorized identity. Low-privilege coverage may
be marked blocked only when no second account exists.

## Knowledge And Admin Boundaries

- Who may approve durable knowledge changes:
- Who may edit `workspace/admin/permissions.md`:
- Who reviews `workspace/admin/knowledge-feedback.md`:
- Which knowledge sources are approved for ingestion:
- Which sources are explicitly out of scope:

## Delivery Boundaries

- Allowed file types for IM delivery:
- Allowed image types for IM delivery:
- Maximum practical attachment size per platform:
- Whether group deliverables are enabled:
- Whether outbound delivery requires manual review:

Generated files must be delivered only from active user deliverables or an
authorized current group deliverables directory.

## Secrets And Runtime Files

- Location of platform runtime configs:
- Owner of local `.env` files:
- Backup remote owner:
- Runtime log retention expectation:
- Local files or directories that must never be sent:

Do not put secrets under `workspace/`, `components/`, docs, or deliverables.

## Validation Evidence

- Release gate run date:
- `bootstrap/doctor.sh` result:
- Platform doctor command and result:
- Permission smoke result:
- IM smoke plan path:
- Blocked live smoke rows and reasons:
- Operator who reviewed the evidence:

Use `docs/release-gate.md` for gate definitions and `docs/im-smoke-sop.md` for
manual IM smoke execution.
