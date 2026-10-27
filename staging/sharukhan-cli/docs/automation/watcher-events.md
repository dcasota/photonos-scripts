# The upstream watcher and its events

[← sharukhan overview](../../README.md)

**Who this is for:** Anyone reading `events.log` or wiring notifications.

## The upstream watcher and its events

```bash
sharukhan watch                  # poll every 900 s (default), record events, notify
sharukhan watch --interval 600   # at least 60
sharukhan watch --once           # one cycle
sharukhan events                 # the last 50 events
sharukhan events --new           # the open ones
sharukhan events ack 412         # handled
sharukhan events ignore 413
```

Branch heads come from `git ls-remote`; a move becomes one typed event in
`memory.db` (`upstream-moved`, `reference-ahead`, `pr-head-moved`,
`sync-needs-decision`, `escalation-proposed`, ...). `MC_NOTIFY` lists the
channels, comma-separated: `file:<path>` (default
`/root/photon-mc/events.log`), `ntfy:https://...`,
`gh-issue:<owner>/<repo>#<n>`. Nothing leaves the host unless a remote channel
is configured.

---

[← sharukhan overview](../../README.md)
