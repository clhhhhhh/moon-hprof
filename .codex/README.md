# Account-quota checkpoint

`quota_guard.py` reads only the current Codex session's local `token_count`
account-limit telemetry. It never reads credentials or sends logs anywhere.
This is a cooperative checkpoint, not a process-killing daemon or billing API.

Run inside the Codex tool environment:

```sh
python .codex/quota_guard.py
```

The session is selected from `CODEX_THREAD_ID`. In a separate terminal, supply
`--session-id` explicitly. It never defaults to whichever other chat was active
most recently. Both short and weekly reported quota windows are checked.

- Exit 0: both available windows are below 50% used.
- Exit 50: at least one window has used 50% or more; stop further task phases.
- Exit 2: quota unknown, stale, expired, or session mismatch; pause and refresh.

`AGENTS.md` instructs the agent to run this before substantial work and between
edit/test/commit phases. A response or tool already executing can overshoot the
threshold; this cannot guarantee an instantaneous hard spending cap. It does
not automatically resume after quota reset.

Local telemetry format is undocumented and may change. For authoritative
account information, use Codex `/status` or the account usage dashboard.
Context occupancy and cumulative token counts are deliberately not interpreted
as account quota. Unchanged log data expires after five minutes by default.

Test the boundary and failure behavior without accessing real account data:

```sh
python -B -m unittest discover -s .codex -p 'test_*.py'
```
