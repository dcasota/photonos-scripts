# ADR-0012 — Host services, one settings file and secret files

Status: accepted, implemented
Date: 2026-10-25
Commits: 1aea1404, 97aac5ef
Docs: [docs/getting-started.md](../../docs/getting-started.md#installing-the-host-services-sharukhan-service), [docs/configuration.md](../../docs/configuration.md)

## Context

The watcher, the timed sync and the builder's shared mount ran as systemd
units written by hand. Their settings came from a shell script that also
exported the guest password, and the escalation's API key lived only in an
interactive session. Nothing could rebuild the units, show their drift, or
give the timed sync the key without putting a secret into a unit file.

## Options considered

1. **Keep hand-written units and shell profiles.** No drift detection; the
   sync service sources a script that prints nothing secret only by
   convention.
2. **Secrets in the unit files or the settings file** (`Environment=`). One
   place, but readable by anything that reads the unit, and copied into every
   backup and diff.
3. **`sharukhan service install|status|remove`**: units rendered from
   templates in the binary, one settings file with every non-secret setting of
   the invoking environment, and secret files (owned by root, mode 0600, in a
   0700 directory) that the settings name through `*_FILE` variables.

## Decision

Option 3. `install` takes the API key and the guest password from the
invoking environment only when asked (`--escalation-key-from-env`,
`--guest-password-from-env`), checks the key against the API first, writes
them atomically, and refuses while a sync run, job or escalation uses the
installed binary. `status` renders what `install` would write from the file
on disk and compares, so `doctor` reports drift. A test keeps every
environment variable the code reads classified as a service setting, a
secret pointer, a secret or not a setting. `sharukhan settings` prints the
effective settings (never a secret) for scripts.

## Consequences

- A new host gets the services with one command; a changed setting is a new
  `install`, not an edit.
- Commands run by hand load the same settings file, so a manual gate and a
  timed sync see the same paths.
- A setting added to the code without classification fails the tests.
