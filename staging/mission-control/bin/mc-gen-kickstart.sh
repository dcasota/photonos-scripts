#!/bin/bash
# mc-gen-kickstart.sh - emit the kickstart JSON for one permutation.
#
# Written to stdout. mc-install.sh base64s it into guestinfo.kickstart.data,
# which POI's isoInstaller reads via vmtoolsd. That is why no permutation
# needs its own ISO: the install-time axes live here, not on the media.
#
# usage: mc-gen-kickstart.sh --fs ext4|btrfs --stig yes|no --variant none|selinux|fips|stigpkgs
#                            --id <perm> [--pubkey <file>] [--ip <addr/cidr>]
set -u
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_here/../lib/common.sh"
. "$(mc_find_config "$_here")"

FS=ext4 STIG=no VARIANT=none PERM=perm PUBKEY="" IPADDR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --fs) FS="$2"; shift 2 ;;
        --stig) STIG="$2"; shift 2 ;;
        --variant) VARIANT="$2"; shift 2 ;;
        --id) PERM="$2"; shift 2 ;;
        --pubkey) PUBKEY="$2"; shift 2 ;;
        --ip) IPADDR="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 64 ;;
    esac
done

KEY=""
[ -n "$PUBKEY" ] && [ -f "$PUBKEY" ] && KEY=$(cat "$PUBKEY")

# The eight names stigenable.py requests when the STIG menu is answered yes.
# A kickstart cannot answer that menu - it is only reachable from the curses
# configurator - so a kickstart that wants STIG must list them itself. That is
# what variant=stigpkgs reproduces, and it is a genuinely different code path
# from the UI row, not a duplicate of it.
KS_STIG_PACKAGES='"audit","rsyslog","openssl-fips-provider","selinux-policy","aide"'

python3 - "$FS" "$STIG" "$VARIANT" "$PERM" "$KEY" "$IPADDR" "$MC_GUEST_PASSWORD" <<'PY'
import json, sys
fs, stig, variant, perm, key, ipaddr, password = sys.argv[1:8]

partitions = [
    {"mountpoint": "/boot/efi", "size": 512,  "filesystem": "vfat"},
    {"mountpoint": "/boot",     "size": 1024, "filesystem": "ext4"},
    {"mountpoint": "/",         "size": 0,    "filesystem": fs},
]

ks = {
    # The hostname carries the permutation id so a guest self-identifies in
    # every log line it ever emits.
    "hostname": "mc-" + perm,
    "password": {"crypted": False, "text": password},
    "disk": "/dev/sda",
    "partitions": partitions,
    "packagelist_file": "packages_minimal.json",
    "linux_flavor": "linux-esx",
    "bootmode": "efi",
    "postinstall": [
        "#!/bin/sh",
        "echo mc-%s > /etc/mission-control-permutation" % perm,
        "systemctl enable sshd.service",
        # Root ssh is how verification gets in. This is a disposable lab VM on
        # a host-only NAT segment, torn down after the run.
        "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config",
    ],
}
if key:
    ks["public_key"] = key

# variant=stigpkgs is the kickstart expression of "STIG = yes".
if variant == "stigpkgs" or stig == "yes":
    ks["additional_packages"] = ["audit", "rsyslog", "openssl-fips-provider",
                                 "selinux-policy", "aide"]
    ks["ansible"] = [{
        "playbook": "/usr/share/ansible/stig-hardening/playbook.yml",
        "logfile": "ansible-stig.log",
        "verbosity": 2,
        "extra-vars": "@/usr/share/ansible/stig-hardening/vars-chroot.yml",
        # PHTN-50-000245 edits tmp.mount, which is package-owned and not
        # %config. Editing it here shows as permanent rpm -V drift and is
        # reverted by the next systemd upgrade, so the build side owns it.
        "skip-tags": ["PHTN-50-000245"],
    }]

# The kickstart-only failure class. On POI 2.8 the security key is only
# present if the author writes it; POI master synthesises selinux for
# everyone. fips is never appended on the UI path on either version, so
# variant=fips is reachable exclusively from a kickstart.
if variant == "selinux":
    ks["security"] = {"selinux": "permissive"}
elif variant == "fips":
    ks["security"] = {"fips": 1}

if ipaddr:
    ks["network"] = {"type": "static", "ip_addr": ipaddr.split("/")[0],
                     "netmask": "255.255.255.0", "gateway": "", "nameserver": ""}
else:
    ks["network"] = {"type": "dhcp"}

print(json.dumps(ks, indent=4))
PY
