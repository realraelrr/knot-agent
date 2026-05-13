# Backup Policy

Knot durable rollback data must be committed and pushed by a Codex app
automation once per day.

## Scope

Back up durable data:

- `AGENTS.md`
- `.skills/knot-setup/`
- `.skills/knot-workflow/`
- `workspace/knowledge/`
- `workspace/admin/`

Do not back up runtime or dependency data:

- `runtime/`
- `components/`
- logs, sockets, locks, local secrets, caches

Session workspaces are not backed up by default. Add
`workspace/sessions/` only when the organization explicitly wants session-level
audit history in git.

## Rules

- Use a customer-controlled git remote named `backup`.
- Do not use `origin`, `scaffold`, or any remote pointing to
  `realraelrr/knot-agent` for durable data backup.
- If the backup root is not a git repository, or remote `backup` is missing,
  report setup required instead of creating an unreviewed remote.
- Stage only the durable backup scope.
- Because the scaffold `.gitignore` intentionally ignores local `workspace/`
  data, use controlled `git add -f` only for the allowlisted durable paths.
  Never use broad `git add -A` for backup.
- Commit only when there are changes.
- Push the current branch to remote `backup` after a successful commit.
- Report the commit hash, pushed branch, or the reason no backup was created.

## Automation

Use `.skills/knot-setup/references/daily-backup-automation.template.md` as the
Codex app automation prompt template.
