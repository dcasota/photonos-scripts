# Data files the automation reads

[← sharukhan overview](../../README.md)

**Who this is for:** Anyone editing the data the automation reads: `variants.conf`, `check-prs.tsv`, `memory.db`.

## Data files the automation reads

### `config/variants.conf`: installer variants and the common branches

```
[variant 2.8]          # the first variant is the default
fix/some-branch
[variant latest]
fix/some-branch
[common]
fix/check-spec-subrelease-aware
[excluded]
fix/experiment  # why it is in no variant (the reason is required)
```

`sharukhan variants` compares it with the fork's open PRs: every listed branch
must be an open PR head and every open PR on the release or `common` branch
must be covered: listed, excluded with a reason, or the parent of a listed
branch (a listed child carries its parent's commits).
`SHARUKHAN_VARIANTS` overrides the path.

### `config/check-prs.tsv`: which PR a check proves

One line per oracle check id followed by one or more PR labels, separated by
whitespace (`guest.selinux PR#31`, or `media.x PR#85 PR#86`; labels are
`PR#<n>` or `POI#<n>`). A `check_result` carries those labels, so a failure
reads as "PR#22 regressed". Comments are whole lines starting with `#`. `sharukhan doctor`
warns when a label names a PR that is no longer open. `SHARUKHAN_CHECK_PRS`
overrides the path.

### `memory.db` and `MEMORY.md`

```bash
sharukhan ingest                         # fold results/ into memory.db (idempotent)
sharukhan db render MEMORY.md            # the database as Markdown
sharukhan db render /path/memory.db out.md
```

The database is the system of record; `MEMORY.md` is a generated view. It is
not kept in the repository - a committed snapshot went stale within weeks and
read as current - so render it locally with `sharukhan db render` whenever you
want to read the database as Markdown. `ingest` reads only results files that
are new or changed since the last ingest (table `ingest_file`), one transaction
per run.

### The embedded canister-equivalent patch

```bash
sharukhan canister-equivalent --check        # is the embedded patch current?
sharukhan canister-equivalent --out new.patch
```

---

[← sharukhan overview](../../README.md)
