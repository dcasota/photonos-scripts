# The network axis

[← sharukhan overview](../../README.md)

**Who this is for:** Someone reading or extending the network rows (n01-n05), and anyone puzzled by a network verdict.

## The network axis

`permutations.tsv` carries an eleventh column, `net`, holding all three network
dimensions in one token:

```
net = <family>-<assignment>-<vlan>
      family      v4 | v6 | dual
      assignment  dhcp | static
      vlan        untag | vlanNNN     (NNN in 1..4094)
```

An absent column, or `-`, means `v4-dhcp-untag` — which is exactly what every
row did before the axis existed, so the column documents the status quo rather
than changing it. `kickstart::tests::the_default_net_token_reproduces_the_legacy_dhcp_kickstart_byte_for_byte`
is the guard for that.

**It is an install-time axis and costs no ISO builds.** The network config
reaches the guest through `guestinfo.kickstart.data` and is applied by POI's
`_setup_network()` against an already-installed root; it never touches the
media, the package set or the installer. `Permutation::iso_key()` deliberately
excludes it, and a test asserts that.

**An unknown token fails `matrix::load`, naming the row.** This is not
fastidiousness: `installer.py` validates only the *top-level* keys of a
kickstart, so a misspelt key inside `network` is silently ignored by POI and
produces a guest with no address and no error message anywhere. The harness is
the only place that typo can ever be caught.

Which POI schema a row exercises follows from its token, and the split is not
arbitrary — `Legacy` is exactly the set the curses configurator can produce:

| token | schema | what it exercises |
| --- | --- | --- |
| `v4-dhcp-untag` | legacy `type: dhcp` | the pre-axis default, all rows outside the n-block |
| `v4-static-untag` | legacy `type: static` | n01 |
| `v4-dhcp-vlanNNN` | legacy `type: vlan` | n05 |
| `v4-static-vlanNNN` | v2 `vlans` | n04 |
| `dual-static-untag` | v2, two families in one `addresses` list | n02 |
| `v6-static-untag` | v2, plus a second NIC | n03 |

All five generated configs were verified by running them through POI's own
`networkmanager.py` offline (`networkmanager.py -D <dir> -f <config>`) and
reading the systemd-networkd files it produced.

### What this host cannot test, and why

These are findings about the host, not about POI, and they are why the block is
five rows rather than twelve.

**IPv6 has three independent blockers, any one sufficient:**

1. `/mnt/c/ProgramData/VMware/vmnetnat.conf` has `natIp6Enable = 0`. The vmnet8
   NAT device emits no router advertisement and offers no IPv6 gateway.
2. **No DHCPv6 server exists on this host in any configuration.**
   `VMnetDHCP.exe` is a VMware port of ISC 2.0 and is IPv4-only;
   `vmnetdhcp.conf` declares only `subnet 192.168.58.0` and
   `subnet 192.168.225.0`. Setting `natIp6Enable = 1` would not create one.
3. **WSL2 runs in NAT networking mode and has no IPv6 stack at all.**
   `.wslconfig` has `networkingMode = Nat`; `/proc/net/if_inet6` holds only
   link-local addresses and `ping -6` answers "Network is unreachable". The
   harness itself cannot reach any guest over IPv6, whatever the hypervisor
   does. Changing this needs `networkingMode = mirrored` and a full WSL
   restart — a global host change.

So DHCPv6 and SLAAC rows are **unrunnable here** and are recorded as such by
`NetSpec::unrunnable_reason` rather than written out and failed. Static IPv6
needs no router, no server and no peer, so it *is* testable: the address is
assigned, DAD completes, and the guest can be asked what it has over an IPv4
path. That is what n02 and n03 do. They could be extended to real IPv6
reachability on a host with an IPv6 router — an ESXi portgroup, or KVM with
`radvd`/`dnsmasq --enable-ra`.

**VLAN has one blocker:**

4. **VMware Workstation 17 has no VLAN backing of any kind.**
   `ethernet0.vlanID` is a vSphere *portgroup* property; `strings` over
   `x64/vmware-vmx.exe`, `vmnetBridge.dll` and `vnetlib.dll` finds no
   VLAN/trunk symbol at all, and the Virtual Network Editor has no VLAN
   concept. Tagging can therefore only happen inside the guest — which is
   exactly what POI's `vlans` config does — and nothing on vmnet8 will answer a
   tagged frame, because the NAT gateway and `VMnetDHCP.exe` are both bound to
   the untagged segment. Bridged mode is no escape: the only uplink is Wi-Fi
   (Intel AX211), and 802.1Q over a bridged wireless adapter does not work.
   There is no wired NIC on this host.

So a VLAN row proves what the installer **configured**, never that tagged
traffic flows, and the oracle asserts accordingly.

### n05 fails for the environment's reason, not POI's

`n05` carries `expect = fails`. That failure is **environmental** — blocker 4
means no switch here will ever answer its tagged DHCP, and no change to Photon
or to the installer would make it pass. This is the opposite of `s02`, which is
a real defect somebody should fix. Do not conflate them.

What n05 *does* prove is that the legacy `type: vlan` conversion ran and wrote
the right files. Its `systemd-networkd-wait-online` failure is asserted
**positively** (`net.wait_online`) and excluded from `guest.failed_units`, so it
is recorded rather than hidden — and so it cannot regress an assertion that has
nothing to do with it.

There is a genuine POI gap underneath: `networkmanager.py` writes only
`[Match]`, `[Network]`, `[NetDev]` and `[VLAN]` sections, so `RequiredForOnline=`
is unreachable from the kickstart schema and an operator who *knows* a link
cannot come up has no way to say so. Written up in
`/root/photon-mc/poi-gap-requiredforonline.md` for filing upstream.

### n03 needs a second NIC, and that now works

An IPv6-only guest is unreachable from this harness (blocker 3), so `n03`'s VMX
carries a second NIC on the same NAT segment doing plain DHCPv4, purely so ssh
has a path in. This was recorded as unproven for a long time — no VM on this
host had ever had two NICs.

**It is proven now.** n03 powers on, installs, and passes 39 checks with 0
failures, with `net.v6_addr fd00:225::4f/64` and DAD complete. The second NIC
also turned out to matter to the install detector, not just to ssh: the guest
takes its DHCPv4 lease on that MANAGEMENT interface, so the lease signal has to
match every MAC the row owns. See *When an install is finished* below — getting
that wrong cost n03 a false `install.booted_from_disk` failure on 2026-09-09.

### When an install is finished, and how that is known

The hardest question this harness asks is *has the install completed*. There
are four signals, and no single one of them is reliable on this host:

| | signal | fires for | why it is not enough alone |
|---|---|---|---|
| a | `root=PARTUUID=` in the serial log | rows whose installed system has a serial console | the installed cmdline carries no `console=ttyS0`, so the log stays 0 bytes and this **never fires here** |
| b | `vmrun getGuestIPAddress` | any row with open-vm-tools | latency is wild: 11 minutes on one c03 run, longer than the whole 2400s timeout on the next |
| c | the host's DHCP lease file, matched on **every NIC the row owns** | any row where some interface takes a lease | a row whose every interface is statically addressed takes none |
| d | SSH on the row's reserved address | static rows | a DHCP row never configures that address |

Together (c) and (d) cover every runnable row.

**(c) must match on every NIC, not just the first.** n03 (`v6-static-untag`)
failed `install.booted_from_disk` on an install that had plainly succeeded: the
guest held `fd00:225::4f/64` with DAD complete and answered 18 checks, and it
had been up since 44 seconds in. Its lease was in the file the whole time,
under the row's own hostname - but carried `00:50:56:3b:00:27` while the lookup
matched `00:50:56:3a:00:27`. That is `mac2` against `mac`: n03 carries a second
NIC and leases on the MANAGEMENT interface, so a filter on the primary MAC
could never match it. Blind by construction, not by timing - waiting longer
would never have helped.

That row is also why (d) cannot cover it: its static address is IPv6 while the
reserved address this harness probes is IPv4, so the SSH probe stays silent.
With (c) matching both NICs, n03 is covered.

**(c) distinguishes the boot source by hostname.** The installer live
environment and the installed system share a MAC, so a lease alone proves
nothing:

```
09:13:54  192.168.225.186  host=photon-installer   <- live installer
09:15:26  192.168.225.192  host=mc-c03             <- installed system
```

Every lookup is bounded below by a timestamp taken before the guest can lease
anything. Leases from PREVIOUS runs of the same row persist under the same MAC
and hostname, so matching on those alone would report an install finished
before the guest powered on - a false pass, and far worse than the false
timeout it replaces.

**(d) checks the SSH banner, not the connection.** The reserved address sits
below the DHCP floor so the pool never hands it out, and the installer live
environment takes a pool lease instead - so nothing answers there until the
installed system has configured its own network. Accepting a bare TCP
handshake as proof of boot is how a detector starts lying again.

The quiet-log line reports all four, because six identical `serial log quiet`
lines over 40 minutes tell a reader nothing about which signal is failing:

```
still waiting: serial size=0, tools ip=none, ssh at 192.168.225.79 silent,
               last lease photon-installer@2026/09/04 16:17:48 192.168.225.155
```

That line is what found (d): every quiet report on the static rows named
`photon-installer` as the last lease, which is the signal saying it cannot see
this row.

---

[← sharukhan overview](../../README.md)
