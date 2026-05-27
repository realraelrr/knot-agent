# Permissions

This file is an agent operating contract, not a security sandbox. Keep it small
and explicit.

| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
|  |  |  |  |  |  |  |  |  |  |  |

Example row:

```text
| example-admin | example-admin | dingtalk | 452965504126566038 | ops-group | cidxxx | dingtalk:user:452965504126566038 | Example Admin | admin | knowledge | Replace with verified /whoami values. |
```

## Roles

- `operator`: may change system config, code, `AGENTS.md`, skills, runtime
  config, IM gateway setup, and this scaffold.
- `admin`: may ingest, edit, delete, approve, and organize knowledge; may
  maintain this permissions file and `knowledge-feedback.md`.
- `member`: may ask questions, use agent capabilities in their own user
  workspace, receive files generated in that workspace, read approved knowledge,
  and append knowledge feedback.

## Defaults

- If a permission check is required and no row matches the user, tell them to
  contact an admin for authorization.
- Only `operator` and `admin` may edit this file.
- `User` is the real person or service account.
- `Workspace` is the human-readable directory slug under `workspace/users/`.
- `Group` is the optional shared workspace slug under `workspace/groups/`.
- Match users by `Identity Key` when present, otherwise by
  `Platform + Platform User ID`. Use `Chat ID` only as source or group
  authorization evidence.
- `Scope` is a human-readable boundary. Use `all`, `system`, `knowledge`,
  `session`, or a department label such as `dept:after_sales`.
- Members must not modify durable knowledge directly.
- Members may append feedback to `knowledge-feedback.md`.
- Knowledge approval requires an explicit `admin` role. `operator` does not
  imply durable knowledge approval.
- Admins record visible diffs, status, and execution before updating durable
  knowledge.
- Operators handle system-level changes.
