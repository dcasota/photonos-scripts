# What an ISO carries: `iso-content`

[← sharukhan overview](../../README.md)

**Who this is for:** Someone looking at a directory of ISOs who wants to know, per ISO, which commit, kernel, systemd and PRs it was built from.

## What an ISO carries: `iso-content`

`sharukhan iso-content [--dir <dir>] [--out <dir>]` writes `<iso>.md` beside every ISO of `--dir`
(default: the ISO store) and `README.md` as an index. Everything is read back, not taken from a name:

- the RPMs from the ISO itself (`/RPMS`, listed by xorriso);
- the base commit the file name ends in, resolved in the gate repository or a build clone: its
  subject, date and merge parents, whether vmware/photon's and the fork's release branch contain it,
  where a commit outside them branches off, and the port branch that contains it or has its tree;
- the Version-Release each package of the base commit's specs declares (`%define`/`%global` literals
  and `%ifarch` expanded for the ISO's architecture), so every RPM that differs is found;
- for each such RPM, the fork's PR heads (now, and every head a sync recorded) and `experimental/*`
  branches whose spec declares exactly that Version-Release. Kernels sharukhan rebuilt itself are
  named for how (`canister=equivalent`, a kernel profile, the Azure remaster); out-of-tree modules
  whose Release carries the kernel's (`.0612115002` is linux 6.12.115-2) are listed with that kernel;
- the ISO's sha256, computed from the file and compared with the cache record of a cache entry that
  links to the ISO (`photon.iso.sha256`); a disagreement is said. The sha256 of each ISO is kept in
  `$MC_WORK/iso-content-sha256.tsv` by name, size and modification time, so only a new or changed ISO
  is hashed again;
- that cache entry's input record (`inputs.txt`);
- the build log: the one a driver log (a build log, a sync stage's log, a run log) named last
  before the line that stored the ISO; for a `run`-driven build, which logs no store line, the
  build log of the same build whose `produced` or `Generating Iso:` line names the ISO, written at
  most ten minutes after it.

An RPM that no candidate declares is listed as unattributed, never guessed.

The ISO store can be written from Windows while sharukhan runs as root, so a report is never
written through a name that already exists: it goes to a new file beside it that is then renamed
over `<iso>.md` (or `README.md`). A symlink planted under that name is replaced, not followed.
