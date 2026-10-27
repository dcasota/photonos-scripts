# Running the matrix: run

[← sharukhan overview](../../README.md)

**Who this is for:** Someone running permutations: what `run` does, step by step, and what it refuses.

## `run` — drive permutations end to end, sequentially

`run` decides what may proceed, serialises against anything already in flight,
proves the media, and records a job so the work is findable after the shell that
started it is gone. Then it drives each row in this process: it tears down
whatever an earlier run left of that row's VM, and runs
`kickstart -> create-vm -> install -> verify -> teardown --purge`. Rows run one
at a time, because ISO builds share `$PHOTON_TREE/stage` and the VM store cannot
hold two installs.

`--dry-run` runs every gate for real — real `df`, real `xorriso`, real process
scan — and executes nothing:

```
$ sharukhan run --dry-run --only k03,k04,s02
selection: 3 row(s)
  3 row(s) can run autonomously

serialisation
  ok      no sharukhan job is running
  ok      no mc-run / mc-build-iso / runPh5 in flight

disk
  ok      / 84G free, VM store 122G free

media
  ok      minimal/2.8/prebuilt     media has photon-os-installer-2.8-7.ph5.x86_64.rpm (expected photon-os-installer-2.8-7*), written 38135s ago

would run 3 row(s), sequentially:
  k03   minimal/2.8/prebuilt     kickstart -> create-vm -> install -> verify -> teardown --purge
  k04   minimal/2.8/prebuilt     kickstart -> create-vm -> install -> verify -> teardown --purge
  s02   minimal/2.8/prebuilt     kickstart -> create-vm -> install -> verify -> teardown --purge

dry run: no job recorded, nothing executed
```

The expected installer NEVR in that `media` line is **derived**, never written
down: the `photon-os-installer.spec` hunk of `variant-patches/poi-2.8.patch` is
isolated (the patch touches ~28 specs, so an unisolated grep reads the wrong
one) and its `+Release:` read; `Version:` comes from `git show origin/5.0:` when
the variant does not set it. A driver that hardcoded `2.9-2` rejected a good ISO
once the spec moved to `2.9-3`, and could not be edited in place because bash
re-reads a running script.

`--dry-run --allow-build` reports the builds a real run would start and starts
none of them: a missing ISO is listed as `would build <key> <path>`, and its
rows as `[build ISO] -> kickstart -> ...`. Until 2026-09-26 it asked
`build::resolve` instead of `build::plan`, and `resolve` knows nothing of dry
runs - it created the cache directory, purged the cached photon-os-installer
RPMs from `stage/RPMS` and started `runPh5_normal.sh`. `resolve` now takes its
decision through `plan` as well, and refuses a missing variant patch before the
purge rather than after it.

The serialisation gate recognises a build by what contends for the shared
common tree, stage and fixed-name sandbox containers - `python3 build.py`,
whatever wrapper runs it - plus the `runPh*` wrapper family, not by a list of
wrapper names. It used to know only `runPh5_normal`, and a build started beside
`runPh7-3-RC4`. `build` and `build-iso` check it too, and `run` checks again
before each ISO it builds, because a run can take many hours:

```
sharukhan: foreign work is in flight: pid 3618556 /bin/sh /tmp/runPh7-3-RC4.5vU5M2.sh /root common experimental/linux-7.3-rc4 ...; pid 3641864 python3 build.py -c build-config.json -t image. ...
```

`--all` selects the matrix and then refuses, individually and out loud, every row
this host cannot drive:

```
$ sharukhan run --dry-run --all
selection: 36 row(s)
  refused p01   mode=ui needs a human at the console: /root/photonos-scripts/staging/mission-control/bin/mc-operator-card.sh --id p01
  [p02 through p16 refused identically - 15 lines elided]
  refused c02   canister=fips0-aarch64 needs aarch64, this host is x86_64
  19 row(s) can run autonomously

[serialisation and disk sections elided - identical to the block above]

media
  ok      minimal/2.8/prebuilt     media has photon-os-installer-2.8-6.ph5.x86_64.rpm (expected photon-os-installer-2.8-6*), written 59760s ago
  ok      minimal/latest/prebuilt  media has photon-os-installer-2.9-3.ph5.x86_64.rpm (expected photon-os-installer-2.9-3*), written 53021s ago
  ok      full/2.8/prebuilt        media has photon-os-installer-2.8-6.ph5.x86_64.rpm (expected photon-os-installer-2.8-6*), written 11288s ago
  ok      full/latest/prebuilt     media has photon-os-installer-2.9-3.ph5.x86_64.rpm (expected photon-os-installer-2.9-3*), written 7773s ago
  REFUSED full/2.8/build           no ISO at /mnt/c/photon-mc/iso-cache/full-poi2.8-build/photon.iso - build it with `/root/photonos-scripts/staging/mission-control/bin/mc-build-iso.sh --iso-type full --poi 2.8 --canister build` (hours, not minutes)
```

`run` refuses a missing ISO rather than building one. `mc-run.sh` would have
built it silently, turning a two-minute invocation into an eleven-hour one.

That capture predates 2026-09-02: c01 was `canister=build` then, so the refused
key reads `full/2.8/build`. It is `full/2.8/equivalent` now — `build` creates a
canister that no row installs, because `canister_build=1` forces
`canister_usage=0` and the kernel every row boots is `linux-esx`, which hardcodes
`canister_build 0`. See ISO-PERMUTATION-MATRIX.md §2b. The refusal behaviour
shown is unchanged.

**A refused gate refuses the whole group.** Pointing at a variant patch that
asks for `2.8-7` while the media carries `2.8-6`:

```
$ MC_VARIANT_PATCH_DIR=/root/sharukhan-demo/variant-patches sharukhan run --dry-run --only k03,k04
selection: 2 row(s)
  2 row(s) can run autonomously

serialisation
  ok      no sharukhan job is running
  ok      no mc-run / mc-build-iso / runPh5 in flight

disk
  ok      / 186G free, VM store 108G free

media
  REFUSED minimal/2.8/prebuilt     media has photon-os-installer-2.8-6.ph5.x86_64.rpm (expected photon-os-installer-2.8-7*), written 60508s ago
sharukhan: every ISO group was refused; nothing would be run
```

**An ISO that is still settling is waited for, not refused.** VMware cannot open
an ISO written moments ago (finding #29: the same 3.9G image was unopenable the
second it landed and instant eight minutes later), so `run` waits until the ISO
is `--settle` seconds old (default 300). The wait is announced with the ISO's
measured age and the seconds left, so it is never a silent pause. It used to
refuse instead, and on 2026-09-13 that skipped a whole group when a campaign's
last build flowed straight into its run, while the report went on showing that
row's result from the day before (finding #61). An ISO that is still *growing*,
or cannot be read, is still refused.

A dry run changes nothing and does not block: it reports the wait a real run
would make and carries on. Forcing the check with an absurd `--settle`:

```
$ sharukhan run --dry-run --only k13 --settle 99999
selection: 1 row(s)
  1 row(s) can run autonomously

serialisation
  ok      no sharukhan job is running
  ok      no mc-run / mc-build-iso / runPh5 in flight

disk
  ok      / 84G free, VM store 122G free

media
  would wait full/latest/prebuilt  /mnt/c/photon-mc/iso-cache/full-poilatest-prebuilt/photon.iso was written 36225s ago; --settle 99999 needs 63774s more (finding #29)
  ok      full/latest/prebuilt     media has photon-os-installer-2.9-4.ph5.x86_64.rpm (expected photon-os-installer-2.9-4*), written 36225s ago

would run 1 row(s), sequentially:
  k13   full/latest/prebuilt     kickstart -> create-vm -> install -> verify -> teardown --purge

dry run: no job recorded, nothing executed
```

Foreign work already in flight is refused too. `--wait-idle <sec>` bounds how
long it will wait first; the default is 0, because a CLI that blocks forever is
the failure being fixed:

```
$ sharukhan run --only k03 --dry-run --wait-idle 20
selection: 1 row(s)
  1 row(s) can run autonomously

serialisation
  ok      no sharukhan job is running
  wait    1 process(es) in flight, waited 0s of 20s
  wait    1 process(es) in flight, waited 15s of 20s
sharukhan: foreign work is in flight: pid 3360289 bash /root/sharukhan-demo/bin/mc-build-iso.sh. ISO builds share $PHOTON_TREE/stage and the VM store cannot hold two installs, so this would corrupt both. Wait, or pass --wait-idle <sec>
```

A real run is a foreground process; background it the way the bash drivers were
backgrounded. It prints the job id and the two commands that act on it.

> **The captures from here to the end of `watch` were produced against a stub
> `mc-run.sh`** — it prints the summary line `mc_result_summary` emits and then
> sleeps — with `MC_BIN=/root/sharukhan-demo/bin` and
> `MC_RUN_LOG_DIR=/root/sharukhan-demo/run-logs`. Nothing is edited; the stub
> paths are visible in the output below. Gating, serialisation, job recording,
> verdict scraping, process-tree teardown and log following are all real. What
> is stubbed is the install underneath: a real 16-row pass takes hours and a
> VMware host, and has **not** been run through this code. The ADR says the same.
>
> **These captures also predate `run` absorbing `mc-run.sh` (2026-09-01).** A row
> no longer runs as a child `mc-run.sh`: it runs in this process as
> `kickstart -> create-vm -> install -> verify -> teardown --purge`, and the hint
> for a powered-on matrix VM now reads ``use `sharukhan teardown --id <id>` ``.
> They are kept for what they show about gating and job handling, not as a
> current transcript.

```
$ nohup sharukhan run --only k03,k04 &
selection: 2 row(s)
  2 row(s) can run autonomously

serialisation
  ok      no sharukhan job is running
  ok      no mc-run / mc-build-iso / runPh5 in flight

disk
  ok      / 186G free, VM store 108G free

media
  ok      minimal/2.8/prebuilt     media has photon-os-installer-2.8-6.ph5.x86_64.rpm (expected photon-os-installer-2.8-6*), written 60400s ago

job 2 (pid 3360126) -> /root/sharukhan-demo/run-logs/run-20260901T115000Z.log
  sharukhan watch --job 2
  sharukhan stop  --job 2
  running k03 (minimal/2.8/prebuilt)
  k03: 13 checks, 13 pass, 0 fail
  running k04 (minimal/2.8/prebuilt)
  k04: 13 checks, 13 pass, 0 fail

job 2 done: 2 of 2 admissible row(s) attempted
evidence: /root/sharukhan-demo/run-logs/run-20260901T115000Z.log
results:  sharukhan report --only k03,k04
```

`k03: 13 checks, 13 pass, 0 fail` is scraped from `mc-run.sh`'s own summary
line. `mc-run.sh` ends with `mc_report_to_file`, so its exit code reflects the
last `tee` rather than the verdict — the scraped line is the evidence, and the
exit code is reported only when there is no line to scrape.

While a job is live, a second `run` is refused by name. This is the
serialisation that mattered: two drivers polling the same idle condition both
woke when it cleared and started an ISO build and a VM install at once.

```
$ sharukhan run --only k05 --dry-run
selection: 1 row(s)
  1 row(s) can run autonomously

serialisation
sharukhan: job 1 (run k03,k04) is still running as pid 3360082; refusing to start a second one. Watch it with `sharukhan watch --job 1` or end it with `sharukhan stop --job 1`
```

---

[← sharukhan overview](../../README.md)
