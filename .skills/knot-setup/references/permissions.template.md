# Permissions

This file is an agent operating contract, not a security sandbox. Keep it small
and explicit.

| Platform | Chat ID | User ID | Session Key | Name | Role | Scope | Notes |
|---|---|---|---|---|---|---|---|
|  |  |  |  |  |  |  |  |

Example row:

```text
| dingtalk | cidxxx | 452965504126566038 | dingtalk:g:cidxxx:452965504126566038 | Example Admin | admin | knowledge | Replace with verified /whoami values. |
```

## Roles

- `operator`: may change system config, code, `AGENTS.md`, skills, runtime
  config, IM gateway setup, and this scaffold.
- `admin`: may ingest, edit, delete, approve, and organize knowledge; may
  maintain this permissions file and `knowledge-feedback.md`.
- `member`: may ask questions, use agent capabilities in their own session
  workspace, receive files generated in that session, read approved knowledge,
  and append knowledge feedback.

## Defaults

- If a permission check is required and no row matches the user, tell them to
  contact an admin for authorization.
- Only `operator` and `admin` may edit this file.
- Match users by `Session Key` when present, then `Platform + Chat ID + User ID`,
  then platform-specific fallback ids.
- `Scope` is a human-readable boundary. Use `all`, `system`, `knowledge`,
  `session`, or a department label such as `dept:after_sales`.
- Members must not modify durable knowledge directly.
- Members may append feedback to `knowledge-feedback.md`.
- Admins review, edit, resolve, or delete feedback entries.
- Operators handle system-level changes.
