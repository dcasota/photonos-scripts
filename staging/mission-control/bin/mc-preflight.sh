#!/bin/bash
# mc-preflight.sh - can this host run the matrix?
# Prints measured values, never a bare OK/FAIL: "tool missing" and "tool
# present but not executable by this user" need different fixes and are
# indistinguishable in a boolean.
set -u
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_here/../lib/common.sh"
. "$(mc_find_config "$_here")"

fail=0
say() { printf '  %-30s %s\n' "$1" "$2"; }
bad() { printf '  %-30s FAIL: %s\n' "$1" "$2"; fail=1; }

echo "== identity =="
say "user" "$(id -un) (uid $(id -u))"

echo "== vmware tooling =="
for t in "$VMRUN" "$VDISKMANAGER"; do
    if   [ ! -e "$t" ]; then bad "$(basename "$t")" "not found at $t"
    elif [ ! -x "$t" ]; then bad "$(basename "$t")" "present but not executable by $(id -un)"
    else say "$(basename "$t")" "executable"; fi
done
if [ -x "$VMRUN" ]; then
    say "vmrun list" "$("$VMRUN" -T ws list 2>&1 | head -1)"
    # Never blanket-stop VMs: other VMs on this host may be live CI runners.
    other=$("$VMRUN" -T ws list 2>/dev/null | tr -d "\r" | grep -c "\.vmx$") || other=0
    say "VMs already running" "$other (mission control only ever touches its own)"
fi

echo "== disk =="
for d in "$MC_VM_ROOT_WSL" "$MC_ISO_CACHE" "$MC_RESULTS_DIR"; do
    mkdir -p "$d" 2>/dev/null || true
    if [ -d "$d" ]; then
        avail=$(df -BG --output=avail "$d" 2>/dev/null | tail -1 | tr -dc '0-9')
        say "$d" "${avail:-?} GiB free"
        # A thin 32 GB disk starts ~6 MB, but a completed Photon install is
        # ~12 GB. Sequential runs with teardown keep this bounded.
        [ -n "${avail:-}" ] && [ "$avail" -lt 25 ] && bad "$d" "under 25 GiB free"
    else bad "$d" "could not create"; fi
done

echo "== iso build tree =="
[ -d "$PHOTON_TREE" ] && say "photon tree" "$PHOTON_TREE ($(git -C "$PHOTON_TREE" rev-parse --short HEAD 2>/dev/null || echo 'not a repo'))" \
                      || bad "photon tree" "$PHOTON_TREE missing"
[ -f "$DOWNSTREAM_PATCH" ] && say "downstream patch" "$(grep -c '^+++ ' "$DOWNSTREAM_PATCH") files" \
                           || bad "downstream patch" "$DOWNSTREAM_PATCH missing"
if [ -f "$DOWNSTREAM_PATCH" ] && [ -d "$PHOTON_TREE" ]; then
    if git -C "$PHOTON_TREE" apply --check "$DOWNSTREAM_PATCH" 2>/dev/null; then
        say "patch applies" "yes"
    else
        bad "patch applies" "no - rebase it or the build guard will refuse"
    fi
fi

# runPh5_normal.sh resolves its patch relative to its own directory, so the
# patch preflight validates must be the patch the build will actually use.
# Two copies of each exist on this host and they had diverged.
RESOLVED="$PHOTON_SCRIPTS/photonos-patches/downstream-fixes.patch"
if [ -f "$RESOLVED" ]; then
    if [ "$(realpath "$RESOLVED" 2>/dev/null)" = "$(realpath "$DOWNSTREAM_PATCH" 2>/dev/null)" ]; then
        say "build resolves patch" "same file preflight checked"
    else
        bad "build resolves patch" "$RESOLVED ($(grep -c '^+++ ' "$RESOLVED") files) != $DOWNSTREAM_PATCH ($(grep -c '^+++ ' "$DOWNSTREAM_PATCH") files)"
    fi
else
    bad "build resolves patch" "$PHOTON_SCRIPTS/runPh5_normal.sh would find no patch at $RESOLVED"
fi

echo "== guest tooling =="
for t in xorriso python3 ssh sshpass; do
    command -v "$t" >/dev/null 2>&1 && say "$t" "$(command -v "$t")" || bad "$t" "not installed"
done

echo "== ssh key =="
if [ -f "$SSH_KEY_DIR/$SSH_KEY_NAME" ]; then say "keypair" "$SSH_KEY_DIR/$SSH_KEY_NAME"
else say "keypair" "absent - mc-run.sh will create it"; fi

echo
[ "$fail" -eq 0 ] && echo "preflight: PASS" || echo "preflight: FAIL"
exit $fail
