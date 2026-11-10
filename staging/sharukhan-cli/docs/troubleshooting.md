# Troubleshooting

[← sharukhan overview](../README.md)

**Who this is for:** Anyone whose build, gate or job did not do what they expected.

## Troubleshooting

### Every ISO group is refused at once

Read the first `REFUSED` line; the others repeat it.

* **`... is missing or has no 'file' binary`** while `docker run --rm
  <composer image> sh -c 'command -v file'` works on the host: Docker's
  default bridge may be gone. `ip link show docker0` fails and the Docker
  journal shows `Failed to add veth... to bridge via netlink: Device does not
  exist`. Containers on `--network none` still work, which is why spec checks
  pass. Restarting Docker (`systemctl restart docker`) recreates `docker0`;
  containers with a restart policy come back by themselves.
* **`build-config.json has no photon-dist-tag`**: a tree sharukhan reads has
  no dist tag. The dist tag, the kernel directory and the branch are read
  from the tree, never assumed.

### The disk fills during a build

A full build needs tens of gigabytes; `run` checks the disk before it starts
a VM, but not other writers on the same disk. Stop the job before the disk is
full, find the writer, then restart:

```bash
df -h /
sharukhan stop --job 90
```

### `stop` and containers

In container mode a build runs inside `docker run`. Every container a job
starts carries the label `sharukhan.job=<id>`, and `sharukhan stop --job <id>`
stops those containers after the processes, saying which, if any, survived:

```bash
docker ps --filter label=sharukhan.job=90
```

### A manual gate after a stopped or failed build

```bash
sharukhan sync reset-trees                 # refuses edits no patch explains
sharukhan variant-patches
sharukhan run --all --allow-build
```

### `nothing provides librpm_sequoia.so.1` when the base sandbox is made

Photon's toolchain step lists `rpm` but not `rpm-sequoia`. When the
rpm-sequoia spec moves to a new version, the purge before a build used to
delete the old rpm-sequoia RPM, while the kept `rpm-libs` still needs its
`librpm_sequoia.so.1`. tdnf then could not install `rpm-build` into the base
sandbox, and every row failed before anything was built. Now the purge keeps
an older package-manager RPM whenever a kept one requires something it alone
provides, and logs `kept <rpm> until the build replaces it: ...`. The
rebuilt, higher version wins in tdnf afterwards. A *higher* stale RPM is
still removed, because it would shadow the rebuild.

A stage purged by an older sharukhan gets the package back from vmware's
published repositories, checked with `rpm -K`, the way `bootstrap` provides
packages.

### Following a job

`sharukhan watch --job <id>` prints the job's state and follows its run log
until it ends (`--once` prints once). Without `--job`, `sharukhan watch` is
the upstream watcher (see its chapter).

```bash
sharukhan watch --job 90 --once      # state and the latest log lines
sharukhan watch --job 90             # follow until the job ends
sharukhan status                     # every job, and whether its process is alive
```

---

[← sharukhan overview](../README.md)
