# Things learned the hard way

[← sharukhan overview](../README.md)

**Who this is for:** Anyone changing sharukhan: the failures that shaped it, so they are not repeated.

## Things learned the hard way

These are encoded in the code, with the reasoning in comments, because each one
cost real time:

- **`permutations.tsv` is whitespace-aligned, not tab-separated.** Splitting on
  `\t` yields zero rows and looks like an empty matrix rather than an error.
- **`vmrun` output is CRLF-terminated.** It is a Windows binary; not stripping
  `\r` makes every comparison fail while the output looks correct.
- **`vmx::placeholders` scans for `@@[A-Z_]+@@`, so a digit ends the token.**
  `@@ETHERNET1@@` substitutes correctly and is then invisible to the contract
  test that keeps the template and the renderer in step. The management NIC's
  placeholder is `@@MGMT_NIC@@` for that reason.
- **New matrix rows must be APPENDED, never inserted.** `identity.rs` derives
  each VM's MAC, UUID and IP from the row *ordinal*, so inserting a row silently
  re-addresses every VM below it.
- **`vmrun` exits 0 even when the VM did not start.** A stale modal dialog in
  the Workstation UI silently swallows the power-on request, so a start has to
  be confirmed against the inventory, not trusted from the exit code.
- **Disk is checked before work starts, not during.** Running out part-way
  leaves a half-written VM and a verdict that means nothing.
- **Evidence observed in one phase is authoritative.** A later phase that fails
  to reproduce it must not overturn it — that produced false failures on every
  row until it was fixed. The media gate is evaluated once per ISO group and
  recorded; per-row processing never re-derives it.
- **`vmrun` exits non-zero when the VM is merely slow.** Attaching a 3.9G ISO
  trips its internal timeout while VMware powers the VM up anyway. Together with
  the line above: the exit code is not evidence in *either* direction, so no
  command here branches on one. The inventory is the sole authority.
- **`pgrep -f` matches the process doing the checking.** The pattern is on the
  checker's own command line. That made a bash waiter wait for itself and made a
  `pkill -f` kill the shell that issued it, twice. `proc::matching` scans
  `/proc` directly, excludes this process, every ancestor, and any other
  `sharukhan` — and matches only `argv[0]`/`argv[1]`, the interpreter and the
  script, never the whole command line. Matching anywhere reports every shell
  that merely *mentions* `mc-run.sh` as running it; that was observed here while
  building this, when the shell that had just written a file of that name was
  counted as a build in flight.
- **Never trust an ISO without reading it.** The expected installer NEVR is
  derived from the variant patch's own `photon-os-installer.spec` hunk, never
  hardcoded. A hardcoded `2.9-2` rejected a good ISO after the spec moved to
  `2.9-3`, and the script could not be fixed in place because bash re-reads a
  running script mid-execution.
- **An ISO that has just been written cannot be opened.** Finding #29: the same
  3.9G image failed every power-on the second it landed on NTFS and opened in
  zero seconds eight minutes later. `run` waits out a too-fresh ISO, announcing
  the wait, rather than starting a VM that will fail for a reason nobody will
  connect to the build. It refused at first, which skipped a whole group of
  rows (finding #61).
- **Serialise on a record, not on an idle poll.** Two drivers polling the same
  idle condition both wake when it clears and both start work. `run` chains on a
  `job` row it owns, and only then checks for foreign processes.
- **A background job outlives the shell that started it.** The `job` table is
  what makes it findable afterwards, and what makes a crashed driver
  distinguishable from a running one.
- **A failed rename is a finding, not a skipped line.** Stashing moved files with
  `rename(...).is_ok()`. When VMware still held a disk open the rename failed
  silently, the disk stayed, and a row "installed" in 18 seconds and passed on an
  installation from the day before (finding #62). Stash failures are logged by
  name, every row tears its VM down first, and `create --recreate` refuses a disk
  that survives.
- **A DHCP lease is not sshd.** The install signal is a lease under the guest's
  own hostname, which comes before sshd listens. One SSH attempt 12 seconds later
  scored a false FAIL on the heaviest row (finding #63). `verify` now retries
  while nothing answers, and never retries an sshd that answered and refused.
- **Check a patch against what a build applies it to.** A build leaves `SPECS`
  patched, so checking a variant patch in the tree reported it stale after every
  build (finding #64). `doctor` reads `origin/<release>` into a temporary index.
- **A temporary name must be unique per call, not per process.** Every thread of
  one process shares a pid, and parallel tests collided on one index file until
  the name carried a counter.
- **"Clean" is not clean at fuzz 0.** `patch` defaults to fuzz 2, rpm's
  `%autopatch` uses `--fuzz=0`. Five 6.12 FIPS patches applied "clean" to
  7.3-rc4 by default and failed at fuzz 0; every patch is judged on its exact
  parent at `--fuzz=0`, and a series is proven by replaying `%prep`.
- **A renamed Kconfig switch drops dependents silently.** 7.x replaced
  `CRYPTO_MANAGER_DISABLE_TESTS` (tests on unless set) with `CRYPTO_SELFTESTS`
  (off unless set), and `CRYPTO_FIPS` depends on it: `olddefconfig` dropped FIPS
  and its jitterentropy settings from Photon's config without an error.
- **Photon's SpecParser reads per-package macros by `Name:`.** A
  `%if 0%{?canister_build}` read before the `Name:` line sees no
  pkg-build-options macros, so the dependency graph demanded the canister in
  the very phase that builds it, while `rpmbuild` itself was right.
- **A harness must not lean on ambient state.** The cascade wrote the canister
  macros but never pointed `build-config.json` at them; `/root/common` still
  named the file from earlier runs, a fresh clone did not, and phase A built a
  canister consumer after seven hours.
- **`make pkgs=a,b` never creates the base sandbox.** After a purge removes
  `sandboxBase` every package fails with "special device overlay does not
  exist". The pre-build now builds each package by its own target.
- **A file walk must not follow a sandbox's mounts.** A failed package's sandbox
  keeps `/proc` mounted; a walk that followed it went through the whole host,
  `/mnt/c` included, and a build sat for half an hour in 9p reads between two
  attempts. Walks stay on their filesystem and skip `stage/photonroot`.
- **A changelog can move to a file the target lacks.** `branch-check` compared
  a spec with the same path only, so a collision in a changelog include passed
  (vmware/photon#1680). A path absent on a side is now compared with every
  changelog of the same package directory there.
- **A cache that fails open is worse than none.** The canister struct-layout
  plugin returned success with an empty database whenever its cache file was
  locked, so under `make -j` layouts could go unchecked. Found while porting the
  canister to 7.3; the 6.12 series carries the same code.

---

[← sharukhan overview](../README.md)
