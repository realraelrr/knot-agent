# Daily Backup Automation Template

Schedule: daily, once per day, local time.

Prompt:

```text
Run the daily Knot rollback backup for the current workspace.

Goal: commit and push durable rollback data once per day.

Use the deterministic backup entrypoint:

```bash
bash bootstrap/knot-backup.sh
```

Never stage or commit runtime/, components/, logs, sockets, locks, local
secrets, caches, node_modules, or dependency checkouts. Do not commit IM runtime
credentials.

If the script reports missing git setup, missing remote `backup`, unsafe remote,
no changes, commit hash, pushed branch, or an exact failure, relay that result.
```
