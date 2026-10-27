#!/bin/bash
# 60-ssh — connect to the appliance, and when that fails, say WHY.
#
# A bare `ssh: connection refused` sends people looking for an onboarding
# gate or a credential bug. Almost always the real answer is one of three
# things this script checks explicitly.
set -u
# --- locate + load the config, FAIL CLOSED --------------------------------
# ${BASH_SOURCE[0]} may point at a COPY in /tmp: the standard WSL workflow
# here is: tr -d CR < script > /tmp/x.sh ; bash /tmp/x.sh  (strips CRLF),
# which breaks any path computed relative to the script. Try the plausible
# locations and REFUSE to continue if none has the config - a previous
# version merely failed to source it and carried on, printing a healthy
# looking first section before dying on unbound variables further down.
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
CFG=""
for _c in "${VM_LAB_DIR:-}/config/vm-lab.env" \
          "$_here/../config/vm-lab.env" \
          "$_here/config/vm-lab.env" \
          "$PWD/config/vm-lab.env" \
          "$PWD/../config/vm-lab.env"; do
    if [ -n "$_c" ] && [ -f "$_c" ]; then CFG="$_c"; break; fi
done
if [ -z "$CFG" ]; then
    echo "FATAL: cannot locate config/vm-lab.env" >&2
    echo "  Run from deploy/vm-lab/, or: export VM_LAB_DIR=/path/to/deploy/vm-lab" >&2
    exit 78
fi
# shellcheck source=../config/vm-lab.env
. "$CFG"
HERE="$_here"

CMD=""
while [ $# -gt 0 ]; do
    case "$1" in
        --cmd) CMD="$2"; shift 2 ;;
        *) echo "usage: $0 [--cmd '<remote command>']"; exit 64 ;;
    esac
done

KEY="$SSH_KEY_DIR/$SSH_KEY_NAME"
TARGET="$SSH_USER@$GUEST_IP_BARE"

echo "=== target ==="
echo "  $TARGET   key: $KEY"

echo
echo "=== 1. do we even have the key? ==="
if [ -f "$KEY" ]; then
    echo "  present: $(ssh-keygen -lf "$KEY.pub" 2>/dev/null)"
else
    echo "  *** MISSING — run 20-make-ssh-key.sh, then REBUILD THE ISO."
    echo "      A key created now cannot reach an already-installed appliance:"
    echo "      root is locked and authorized_keys was written at install time."
    exit 3
fi

echo
echo "=== 2. is the guest reachable at all? ==="
if command -v ping >/dev/null 2>&1 && ping -c1 -W2 "$GUEST_IP_BARE" >/dev/null 2>&1; then
    echo "  ICMP: replies"
else
    echo "  ICMP: no reply (may be filtered — not conclusive on its own)"
fi
if command -v nc >/dev/null 2>&1; then
    if nc -z -w3 "$GUEST_IP_BARE" 22 2>/dev/null; then
        echo "  port 22: OPEN"
    else
        echo "  port 22: CLOSED/unreachable"
        echo "    Common causes, in the order they actually occur:"
        echo "      a) the guest never got $GUEST_STATIC_IP — the kickstart writes"
        echo "         /etc/systemd/network/10-eth0-static.network at install time;"
        echo "         check section 3 of 40-check-staging.sh --iso ..."
        echo "      b) the VM is not running, or is still installing"
        echo "      c) the MAC drifted, so the NAT lease moved to another address"
    fi
fi

echo
echo "=== 3. try it ==="
# BatchMode: never sit at a password prompt — root is locked and there is no
# password to give, so an interactive prompt is always a dead end here.
SSH_OPTS="-i $KEY -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8"
# shellcheck disable=SC2086
if [ -n "$CMD" ]; then
    ssh $SSH_OPTS "$TARGET" "$CMD"
    rc=$?
else
    ssh $SSH_OPTS "$TARGET" 'echo "connected as $(id -un)@$(hostname)"; cat /etc/spagat/appliance-info.toml 2>/dev/null | grep -E "^build_label"'
    rc=$?
fi

if [ "$rc" -ne 0 ]; then
    echo
    echo "  ssh exited $rc."
    echo "  If it was 'Permission denied (publickey)': the ISO did not carry"
    echo "  this key. Both SPAGAT_OPERATOR_AUTHORIZED_KEY and"
    echo "  IPHASE6_TEST_SSH_PUBKEY default to EMPTY, so a build where neither"
    echo "  was exported ships an EMPTY authorized_keys. Verify with:"
    echo "      scripts/40-check-staging.sh --iso <the-iso-you-installed>"
    echo "  and rebuild after exporting the key. There is no way to add it to"
    echo "  an installed appliance without console access."
fi
exit $rc
