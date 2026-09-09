#!/bin/bash
# 20-make-ssh-key — create the lab keypair and print the exact exports the ISO
# build needs.
#
# 🚨 READ THIS BEFORE ANYTHING ELSE
#
# SSH access to the appliance is decided AT ISO BUILD TIME. There is no
# post-install path: root installs LOCKED by default
# (DEFAULT_SPAGAT_ROOT_PASSWORD_HASH = "*"), and both SSH key variables
# default to EMPTY:
#
#   SPAGAT_OPERATOR_AUTHORIZED_KEY = ""   (iso-phase6 config.rs)
#   IPHASE6_TEST_SSH_PUBKEY        = ""
#
# so a normal build ships `operator`'s authorized_keys with correct 0600
# perms and NO CONTENT. That is the whole of the long-running "no accepted
# SSH key" symptom — not an onboarding gate, not a credential bug: nobody
# exported the variable.
#
# If you build an ISO without exporting one of these, your only way into the
# guest is the serial console.
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

KEY="$SSH_KEY_DIR/$SSH_KEY_NAME"

mkdir -p "$SSH_KEY_DIR"
chmod 0700 "$SSH_KEY_DIR"

if [ -f "$KEY" ]; then
    echo "=== keypair already exists — reusing (not regenerating) ==="
else
    echo "=== generating ed25519 keypair ==="
    # No passphrase: this is a disposable lab key for an unattended install.
    # It is NOT an operator credential and must never be reused elsewhere.
    # No 'set -e' in this script, so a failed keygen would otherwise fall
    # through to 'cat "$KEY.pub"' and report a missing file instead of the
    # real cause.
    if ! ssh-keygen -t ed25519 -N '' -C "spagat-vm-lab@$(hostname)" -f "$KEY"; then
        echo "FAIL: ssh-keygen could not create $KEY" >&2
        exit 5
    fi
fi
chmod 0600 "$KEY"
chmod 0644 "$KEY.pub"

echo
echo "  private: $KEY"
echo "  public : $KEY.pub"
echo "  finger : $(ssh-keygen -lf "$KEY.pub")"

PUB="$(cat "$KEY.pub")"

echo
echo "=============================================================="
echo " EXPORT THESE BEFORE BUILDING THE ISO"
echo "=============================================================="
cat <<EOF

# Bake this key into operator's authorized_keys:
export SPAGAT_OPERATOR_AUTHORIZED_KEY='$PUB'

# ...or as the APPENDED second key (the opt-in automated-test path):
export IPHASE6_TEST_SSH_PUBKEY='$PUB'

# Static IP the guest will claim (kickstart writes
# /etc/systemd/network/10-eth0-static.network):
export IPHASE6_INSTALL_STATIC_IP='$GUEST_STATIC_IP'

EOF
echo "=============================================================="
echo
echo "Then build the ISO in the SAME shell, e.g.:"
echo "  make iso-test BUILD_MANIFEST=... OUTPUT_ISO=..."
echo
echo "VERIFY the key actually landed in the ISO (do not assume) with:"
echo "  scripts/40-check-staging.sh --iso <path-to.iso>"
echo
echo "Root stays LOCKED regardless. To also set a root password you must pass"
echo "BOTH --root-password-file AND --operator-medium-dir to install-from-iso"
echo "(all-or-nothing, BUG-N91); passing one alone is a hard error."
