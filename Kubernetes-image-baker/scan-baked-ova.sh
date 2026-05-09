#!/bin/bash
set -euo pipefail

# =============================================================================
# scan-baked-ova.sh — three-stage scan of a baked Photon/Ubuntu/RHEL OVA:
#
#   1. Syft  — generate CycloneDX SBOM from the rootfs
#   2. Grype — scan the SBOM for known CVEs (gates on $GRYPE_FAIL_ON severity)
#   3. STIG  — boot the OVA in QEMU/KVM and run cinc-auditor over SSH
#              (skipped if SKIP_STIG=1 or /dev/kvm is unavailable)
#
# All version pins, OS target, registry, and thresholds live in lib/common.sh.
# Override any of them via env: e.g.  OS_TARGET=ubuntu SKIP_STIG=1 ./scan-baked-ova.sh ova path
# =============================================================================

OVA_PATH="${1:?usage: $0 <ova-path> <image-name>}"
IMAGE_NAME="${2:?usage: $0 <ova-path> <image-name>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

SBOM_DIR="${SBOM_DIR:-${WORKDIR}/sbom}"
REPORT_DIR="${REPORT_DIR:-${WORKDIR}/scan-reports}"
SCAN_WORK="${SCAN_WORK:-${WORKDIR}/.scan-work}"
mkdir -p "$SBOM_DIR" "$REPORT_DIR" "$SCAN_WORK"

MNT="$(mktemp -d)"
NBD_DEV=""
VM_PIDFILE=""
cleanup() {
    [ -n "$VM_PIDFILE" ] && [ -f "$VM_PIDFILE" ] && kill "$(cat "$VM_PIDFILE")" 2>/dev/null || true
    sudo umount "$MNT" 2>/dev/null || true
    [ -n "$NBD_DEV" ] && sudo qemu-nbd --disconnect "$NBD_DEV" 2>/dev/null || true
    rm -rf "$MNT"
}
trap cleanup EXIT

# =============================================================================
step "[setup] Tool prereqs (auto-detected pkg manager: $PKG_MGR)"
# =============================================================================
NEED=()
need jq          || NEED+=(jq)
need git         || NEED+=(git)
need qemu-img    || case "$PKG_MGR" in apt-get) NEED+=(qemu-utils);; *) NEED+=(qemu);; esac
need tar         || NEED+=(tar)
need curl        || NEED+=(curl)
if [ "$SKIP_STIG" != "1" ]; then
    need qemu-system-x86_64 || case "$PKG_MGR" in apt-get) NEED+=(qemu-system-x86);; *) NEED+=(qemu-kvm);; esac
    need cloud-localds      || case "$PKG_MGR" in apt-get) NEED+=(cloud-image-utils);; *) NEED+=(cloud-utils);; esac
fi
[ "${#NEED[@]}" -gt 0 ] && pkg_install "${NEED[@]}"

# Anchore tools
need syft  || curl -sSfL https://get.anchore.io/syft  | sudo sh -s -- -b /usr/local/bin
need grype || curl -sSfL https://get.anchore.io/grype | sudo sh -s -- -b /usr/local/bin

# cinc-auditor
if [ "$SKIP_STIG" != "1" ] && ! need cinc-auditor; then
    info "Installing cinc-auditor"
    curl -sSL https://omnitruck.cinc.sh/install.sh | sudo bash -s -- -P cinc-auditor
fi

# =============================================================================
step "[1/3] Unpack OVA + mount rootfs read-only"
# =============================================================================
UNPACK_DIR="$SCAN_WORK/ova-unpack"
rm -rf "$UNPACK_DIR" && mkdir -p "$UNPACK_DIR"
tar -xf "$OVA_PATH" -C "$UNPACK_DIR"

VMDK="$(find "$UNPACK_DIR" -name '*.vmdk' | head -1)"
[ -n "$VMDK" ] || die "no VMDK in $OVA_PATH"

RAW="$SCAN_WORK/disk.raw"
QCOW="$SCAN_WORK/disk.qcow2"
qemu-img convert -O raw   "$VMDK" "$RAW"
qemu-img convert -O qcow2 "$VMDK" "$QCOW"

sudo modprobe nbd max_part=16
NBD_DEV="/dev/nbd0"
sudo qemu-nbd --connect="$NBD_DEV" --read-only "$RAW"
sleep 2

# Mount the largest partition (rootfs). For LVM-based images, swap to vgscan.
ROOT_PART="$(lsblk -bnro NAME,SIZE "$NBD_DEV" | sort -k2 -n | tail -1 | awk '{print "/dev/"$1}')"
sudo mount -o ro "$ROOT_PART" "$MNT"

# =============================================================================
step "[2/3] Syft + Grype"
# =============================================================================
SBOM_FILE="$SBOM_DIR/${IMAGE_NAME}.cdx.json"
sudo syft "dir:$MNT" -o cyclonedx-json="$SBOM_FILE"

GRYPE_JSON="$REPORT_DIR/${IMAGE_NAME}.grype.json"
GRYPE_TXT="$REPORT_DIR/${IMAGE_NAME}.grype.txt"
grype "sbom:$SBOM_FILE" -o table | tee "$GRYPE_TXT"
grype "sbom:$SBOM_FILE" -o json  > "$GRYPE_JSON"

set +e
grype "sbom:$SBOM_FILE" --fail-on "$GRYPE_FAIL_ON" -o table > /dev/null
GRYPE_RC=$?
set -e
[ "$GRYPE_RC" -eq 0 ] || die "Grype found findings >= $GRYPE_FAIL_ON (see $GRYPE_TXT)"
info "Grype: no findings >= $GRYPE_FAIL_ON"

sudo umount "$MNT"
sudo qemu-nbd --disconnect "$NBD_DEV"
NBD_DEV=""

# =============================================================================
if [ "$SKIP_STIG" = "1" ]; then
    step "[3/3] STIG step skipped (SKIP_STIG=1)"
    exit 0
fi
[ -r /dev/kvm ] && [ -w /dev/kvm ] || die "/dev/kvm not accessible — re-run with SKIP_STIG=1 or use a host with virtualization"

step "[3/3] STIG via VM boot + cinc-auditor"
# =============================================================================
# Pick the right STIG profile based on OS_TARGET. Default repo is VMware's
# dod-compliance-and-automation; ubuntu/rhel scans need different profiles.
case "$OS_TARGET" in
    photon)
        STIG_REPO="https://github.com/vmware/dod-compliance-and-automation.git"
        STIG_PATH="photon/$PHOTON_VERSION"
        ;;
    ubuntu)
        STIG_REPO="https://github.com/CMSgov/cinc-profiles.git"
        STIG_PATH="cis-ubuntu-22.04-level-1-lts"
        ;;
    rhel)
        STIG_REPO="https://github.com/cinc-project/inspec-cis-rhel9-baseline.git"
        STIG_PATH="."
        ;;
    *)  die "no STIG mapping for OS_TARGET=$OS_TARGET — set SKIP_STIG=1" ;;
esac

PROFILE_BASE="$SCAN_WORK/stig-content"
if [ ! -d "$PROFILE_BASE/.git" ]; then
    git clone --depth 1 --branch "$STIG_REPO_REF" "$STIG_REPO" "$PROFILE_BASE"
else
    git -C "$PROFILE_BASE" fetch --depth 1 origin "$STIG_REPO_REF"
    git -C "$PROFILE_BASE" reset --hard FETCH_HEAD
fi

PROFILE_DIR=$(find "$PROFILE_BASE/$STIG_PATH" -name inspec.yml -printf '%h\n' | head -1)
[ -n "$PROFILE_DIR" ] || die "no inspec.yml under $STIG_PATH"
info "Using STIG profile at $PROFILE_DIR"

(cd "$PROFILE_DIR" && cinc-auditor vendor --overwrite) || true

# Cloud-init seed
VM_DIR="$SCAN_WORK/vm"
rm -rf "$VM_DIR" && mkdir -p "$VM_DIR"
SSH_KEY="$VM_DIR/scan_key"
ssh-keygen -t ed25519 -N '' -f "$SSH_KEY" -q
cat > "$VM_DIR/user-data" <<EOF
#cloud-config
users:
  - name: root
    ssh_authorized_keys:
      - $(cat "${SSH_KEY}.pub")
ssh_pwauth: false
disable_root: false
EOF
echo 'instance-id: stig-scan' > "$VM_DIR/meta-data"
cloud-localds "$VM_DIR/seed.iso" "$VM_DIR/user-data" "$VM_DIR/meta-data"

SSH_PORT="${SSH_PORT:-2222}"
VM_PIDFILE="$VM_DIR/qemu.pid"
qemu-system-x86_64 -enable-kvm -m 2048 -smp 2 -nographic -daemonize \
    -drive file="$QCOW",if=virtio \
    -drive file="$VM_DIR/seed.iso",if=virtio,format=raw \
    -netdev user,id=n0,hostfwd=tcp::${SSH_PORT}-:22 \
    -device virtio-net,netdev=n0 \
    -pidfile "$VM_PIDFILE"

info "Waiting up to 5 minutes for VM SSH on port $SSH_PORT"
for _ in $(seq 1 60); do
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=2 -p "$SSH_PORT" root@127.0.0.1 true 2>/dev/null \
        && { SSH_READY=1; break; }
    sleep 5
done
[ "${SSH_READY:-0}" = "1" ] || die "VM did not become reachable via SSH"

STIG_JSON="$REPORT_DIR/${IMAGE_NAME}.stig.json"
INPUTS_ARG=()
[ -n "${STIG_INPUTS_FILE:-}" ] && INPUTS_ARG=(--input-file "$STIG_INPUTS_FILE")

set +e
cinc-auditor exec "$PROFILE_DIR" \
    -t "ssh://root@127.0.0.1:$SSH_PORT" \
    -i "$SSH_KEY" \
    --reporter "cli" "json:$STIG_JSON" \
    --no-create-lockfile \
    "${INPUTS_ARG[@]}"
STIG_RC=$?
set -e
info "cinc-auditor exit: $STIG_RC (0=pass, 100=control failures, other=tool error)"

shred -u "$SSH_KEY" "${SSH_KEY}.pub" 2>/dev/null || rm -f "$SSH_KEY" "${SSH_KEY}.pub"

[ -s "$STIG_JSON" ] || die "no STIG JSON report produced"

HIGH_FAILED=$(jq '[.profiles[].controls[] | select(.results[]?.status == "failed") | select(.impact >= 0.7)] | length' "$STIG_JSON")
TOTAL_FAILED=$(jq '[.profiles[].controls[] | select(.results[]?.status == "failed")] | length' "$STIG_JSON")

info "STIG: $TOTAL_FAILED failed controls ($HIGH_FAILED high-impact)"
if [ "$STIG_FAIL_ON_HIGH" = "1" ] && [ "$HIGH_FAILED" -gt 0 ]; then
    die "$HIGH_FAILED high-impact STIG controls failed"
fi

echo
echo "=== All scans passed ==="
echo "  SBOM:  $SBOM_FILE"
echo "  Grype: $GRYPE_TXT  /  $GRYPE_JSON"
echo "  STIG:  $STIG_JSON"
