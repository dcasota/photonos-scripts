#!/bin/bash
# mc-operator-card.sh - what a human must enter for one interactive permutation.
#
# Generated from permutations.tsv, never hand-written, so the instructions
# cannot drift from the matrix they are supposed to exercise.
#
# usage: mc-operator-card.sh --id <perm>
set -u
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_here/../lib/common.sh"
. "$(mc_find_config "$_here")"
TSV="$_here/../config/permutations.tsv"

PERM=""
while [ $# -gt 0 ]; do
    case "$1" in --id) PERM="$2"; shift 2 ;; *) mc_die "unknown arg: $1" 64 ;; esac
done
[ -n "$PERM" ] || mc_die "--id is required" 64

read -r _ ISO POI STIG FS MODE VARIANT DOC EXPECT <<EOF
$(grep -vE '^#|^$' "$TSV" | awk -v p="$PERM" '$1==p')
EOF
[ -n "${ISO:-}" ] || mc_die "permutation $PERM not found" 65

VM="mc-$PERM"
IDX=$(mc_perm_index "$PERM")

cat <<TXT
PERMUTATION $PERM   (ISO $ISO / installer $POI / STIG $STIG / $FS / interactive)

  VM name       : $VM
  Console       : VMware Workstation -> $VM
  Matrix says   : $DOC        Expected with the PRs: $EXPECT

  ENTER IN THE INSTALLER
    1. License                 accept
    2. Disk                    /dev/sda  ->  choose CUSTOM partitioning
                               (auto-partition always makes ext4, so a
                                filesystem row can only be reached by hand)
       /boot/efi   512 MB  vfat
       /boot      1024 MB  ext4
       /             rest  $FS      <-- the axis under test
    3. Hostname                mc-$PERM
    4. Root password           $MC_GUEST_PASSWORD
    5. "Apply STIG hardening"  $(if [ "$STIG" = yes ]; then echo "YES  <-- the axis under test"; else echo "NO"; fi)
       (this menu is the reason $PERM cannot be automated: it exists only in
        the curses configurator, so no kickstart can answer it)
    6. Let it install and reboot on its own.

  Tell me when the install has finished and I will verify it.
TXT
