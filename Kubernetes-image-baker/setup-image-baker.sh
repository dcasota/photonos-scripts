#!/bin/bash
set -euo pipefail

# =============================================================================
# setup-image-baker.sh — end-to-end VKR image baker (multi-OS).
#
# All version pins, OS targets, paths and toggles live in lib/common.sh.
# Override any of them via env: e.g.  OS_TARGET=ubuntu ./setup-image-baker.sh
#
# Pipeline:
#   1. Host prereqs (auto-detected via detect_pkg_mgr)
#   2. BuildKit + insecure localhost:5000
#   3. VCF CLI + kubernetes-release plugin (pinned)
#   4. Local docker registry (registry:2)
#   5. Patch /usr/bin/mkova.sh to use bsdtar (Photon's tar is toybox)
#   6. Build vkr-wrapper image (kubernetesSpec)
#   7. Build per-target <OS>-with-containerd image (osSpec.image)
#   8. Generate $WORKDIR/photon-bpf.yaml (or $OS_NAME-bpf.yaml)
#   9. Run vcf kr bake (produces VMDK; v3.6.2's own OVA step is broken)
#  10. Assemble OVA out-of-band with mkova.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"
dump_config

# Preflight: OS-target-specific requirements that aren't installable.
case "$OS_TARGET" in
    rhel)
        # The bake's RhelBaker registers the chroot with Red Hat's CDN via
        # subscription-manager; that requires a valid RH account.
        if [ -z "${RH_USERNAME:-}" ] || [ -z "${RH_PASSWORD:-}" ]; then
            die "RHEL bake requires RH_USERNAME and RH_PASSWORD env vars (Red Hat
       subscription credentials). The bake registers the chroot with
       subscription-manager to install RPMs from Red Hat's CDN; there is
       no offline alternative supported by the v3.6.2 plugin.

       Either:
         export RH_USERNAME=… RH_PASSWORD=… ./setup-image-baker.sh
       …or pick a different OS_TARGET (photon, ubuntu)."
        fi
        ;;
esac

# =============================================================================
step "[1/10] Host prereqs"
# =============================================================================
NEED=()
need curl       || NEED+=(curl)
need docker     || NEED+=(docker)
need mkfs.xfs   || NEED+=(xfsprogs)
need bsdtar     || case "$PKG_MGR" in tdnf|dnf) NEED+=(libarchive);; apt-get) NEED+=(libarchive-tools);; esac
need gcc        || NEED+=(gcc)
need qemu-img   || case "$PKG_MGR" in tdnf|dnf) NEED+=(qemu-img);; apt-get) NEED+=(qemu-utils);; esac
need git        || NEED+=(git)
need make       || NEED+=(make)
case "$PKG_MGR" in
    tdnf|dnf) need ld     || NEED+=(binutils glibc-devel linux-api-headers) ;;
    apt-get)  need ld     || NEED+=(binutils libc6-dev linux-libc-dev) ;;
esac
# open-vmdk: package only exists on Photon. On any other distro we build it
# from source (small CMake project, ~30 s), so the rest of the script can
# rely on /usr/local/bin/{vmdk-convert,mkova.sh}.
case "$PKG_MGR" in
    tdnf|dnf) need vmdk-convert || NEED+=(open-vmdk) ;;
    apt-get)  : ;;   # handled below
esac
[ "${#NEED[@]}" -gt 0 ] && pkg_install "${NEED[@]}"

if ! need vmdk-convert; then
    info "Building open-vmdk from source (no distro package available)"
    case "$PKG_MGR" in
        apt-get) pkg_install cmake libz-dev ;;
        tdnf|dnf) pkg_install cmake zlib-devel ;;
    esac
    OVMDK_DIR="$(mktemp -d)"
    git clone --depth 1 https://github.com/vmware/open-vmdk.git "$OVMDK_DIR"
    ( cd "$OVMDK_DIR" && cmake . && make && sudo make install )
    rm -rf "$OVMDK_DIR"
fi

# Docker daemon must be up for the local registry
if need systemctl && ! systemctl is-active --quiet docker 2>/dev/null; then
    sudo systemctl enable --now docker || true
fi

# =============================================================================
step "[2/10] BuildKit ${BUILDKIT_VERSION} + insecure ${REGISTRY}"
# =============================================================================
if [ ! -x /usr/local/bin/buildkitd ]; then
    BK_TGZ="buildkit-${BUILDKIT_VERSION}.linux-${ARCH}.tar.gz"
    TMP="$(mktemp -d)"
    curl -fL -o "$TMP/$BK_TGZ" \
        "https://github.com/moby/buildkit/releases/download/${BUILDKIT_VERSION}/${BK_TGZ}"
    sudo tar -xzf "$TMP/$BK_TGZ" -C /usr/local/
    rm -rf "$TMP"
fi

sudo mkdir -p /etc/buildkit /var/lib/buildkit
sudo tee /etc/systemd/system/buildkitd.service > /dev/null <<'EOF'
[Unit]
Description=BuildKit
After=network.target

[Service]
ExecStart=/usr/local/bin/buildkitd
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo tee /etc/buildkit/buildkitd.toml > /dev/null <<EOF
[registry."${REGISTRY}"]
  http = true
  insecure = true
EOF
sudo systemctl daemon-reload
sudo systemctl enable buildkitd
sudo systemctl restart buildkitd
for _ in $(seq 1 30); do
    sudo buildctl --addr unix:///run/buildkit/buildkitd.sock debug workers >/dev/null 2>&1 && break
    sleep 1
done

# =============================================================================
step "[3/10] VCF CLI ${VCF_VERSION} + kubernetes-release ${KR_PLUGIN_VERSION}"
# =============================================================================
if ! need vcf; then
    TMP="$(mktemp -d)"
    curl -fL -o "$TMP/vcf-cli.tar.gz" \
        "https://packages.broadcom.com/artifactory/vcf-distro/vcf-cli/linux/${ARCH}/${VCF_VERSION}/vcf-cli.tar.gz"
    tar -xzf "$TMP/vcf-cli.tar.gz" -C "$TMP"
    sudo install -m 0755 "$TMP/vcf-cli-linux_${ARCH}" /usr/local/bin/vcf
    rm -rf "$TMP"
fi
vcf plugin install kubernetes-release --version "$KR_PLUGIN_VERSION"

# =============================================================================
step "[4/10] Local registry on ${REGISTRY}"
# =============================================================================
if ! docker ps --format '{{.Names}}' | grep -q '^local-registry$'; then
    docker rm -f local-registry 2>/dev/null || true
    docker run -d --restart=always -p "${REGISTRY_PORT}:5000" \
        --name local-registry registry:2
fi

# =============================================================================
step "[5/10] Patch mkova.sh to use bsdtar"
# =============================================================================
# Photon's /usr/bin/tar is toybox — lacks --format=ustar. mkova.sh uses
# 'tar --format=ustar', so swap to 'bsdtar' which supports it.
# Idempotent: only patch if 'bsdtar' isn't already wired in (a substring
# match on 'tar --format=ustar' would otherwise re-fire and produce
# 'bsdbsdtar' on the second run).
if [ -f /usr/bin/mkova.sh ] && ! grep -q 'bsdtar --format=ustar' /usr/bin/mkova.sh; then
    sudo sed -i 's|tar --format=ustar|bsdtar --format=ustar|g' /usr/bin/mkova.sh
fi

# =============================================================================
step "[6/10] Build vkr-wrapper:${VKR_K8S_VERSION} (kubernetesSpec)"
# =============================================================================
WRAPPER_DIR="$(mktemp -d)"
trap 'rm -rf "$WRAPPER_DIR"' EXIT
cat > "$WRAPPER_DIR/Dockerfile" <<EOF
# syntax=docker/dockerfile:1.4
FROM projects.packages.broadcom.com/vsphere/iaas/kubernetes-release/${VKR_K8S_VERSION}/vkr-artifact-server:${VKR_TAG} AS src
FROM ${OS_BASE_IMAGE} AS extractor
WORKDIR /out
COPY --from=src /data/artifacts/ /out/
RUN set -e; \\
    for f in /out/*.tar.bz2; do [ -e "\$f" ] || continue; tar -xjf "\$f" -C /out && rm "\$f"; done; \\
    for f in /out/*.tar.gz;  do [ -e "\$f" ] || continue; tar -xzf "\$f" -C /out && rm "\$f"; done; \\
    # Strip non-target OSImage YAMLs and references
    for d in photon ubuntu rhel windows; do \\
        if [ "\$d" != "${OS_NAME}" ]; then \\
            rm -f /out/metadata/config/OSImage-\${d}-*.yml; \\
            sed -i "/name: \${d}-/d; /name: \${d}_/d" /out/metadata/config/TanzuKubernetesRelease.yml || true; \\
        fi; \\
    done; \\
    if [ -f /out/metadata/unified-tkr-vsphere.tar.gz ]; then \\
        tmp=\$(mktemp -d); \\
        tar -xzf /out/metadata/unified-tkr-vsphere.tar.gz -C "\$tmp"; \\
        for d in photon ubuntu rhel windows; do \\
            if [ "\$d" != "${OS_NAME}" ]; then \\
                rm -f "\$tmp"/config/OSImage-\${d}-*.yml; \\
                sed -i "/name: \${d}-/d; /name: \${d}_/d" "\$tmp"/config/TanzuKubernetesRelease.yml || true; \\
            fi; \\
        done; \\
        tar -czf /out/metadata/unified-tkr-vsphere.tar.gz -C "\$tmp" .; \\
        rm -rf "\$tmp"; \\
    fi
FROM scratch
COPY --link --from=extractor /out/ /
EOF

sudo buildctl --addr unix:///run/buildkit/buildkitd.sock build \
    --frontend dockerfile.v0 \
    --local context="$WRAPPER_DIR" \
    --local dockerfile="$WRAPPER_DIR" \
    --output "type=image,name=${WRAPPER_REPO}:${VKR_K8S_VERSION},push=true,registry.insecure=true"

# =============================================================================
step "[7/10] Build ${OS_NAME}-with-containerd:${OS_VERSION} (osSpec.image)"
# =============================================================================
# The v3.6.2 baker's LLB pipeline OMITS the cri-containerd.tar extraction step
# in standalone mode, and later calls 'systemctl enable containerd' which
# fails because containerd.service does not exist. We pre-stage a base image
# that already has cri-containerd extracted, plus stub kubelet/registry units
# and an LD_PRELOAD shim that strips backslashes from /proc/cmdline (WSL
# host fix for the baker's /tmp/export-system-info.sh -> jq exit 5 bug).
PHOTON_DIR="$(mktemp -d)"
cat > "$PHOTON_DIR/cmdline-fixup.c" <<'EOF'
// LD_PRELOAD shim: redirect open()/openat()/fopen() of /proc/cmdline to
// /etc/cmdline-sanitized. Used to neutralise WSL's `initrd=\initrd.img`
// that breaks the baker's JSON-encoded export-system-info.sh.
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdarg.h>
#include <string.h>
#include <dlfcn.h>
#include <stdio.h>
static const char SRC[] = "/proc/cmdline";
static const char DST[] = "/etc/cmdline-sanitized";
#define REWRITE(p) ((p) && strcmp((p), SRC) == 0 ? DST : (p))
int open(const char *p, int flags, ...) {
    static int (*r)(const char *, int, ...) = NULL;
    if (!r) r = dlsym(RTLD_NEXT, "open");
    p = REWRITE(p);
    if (flags & O_CREAT) { va_list a; va_start(a, flags); mode_t m = va_arg(a, mode_t); va_end(a); return r(p, flags, m); }
    return r(p, flags);
}
int open64(const char *p, int flags, ...) {
    static int (*r)(const char *, int, ...) = NULL;
    if (!r) r = dlsym(RTLD_NEXT, "open64");
    p = REWRITE(p);
    if (flags & O_CREAT) { va_list a; va_start(a, flags); mode_t m = va_arg(a, mode_t); va_end(a); return r(p, flags, m); }
    return r(p, flags);
}
int openat(int d, const char *p, int flags, ...) {
    static int (*r)(int, const char *, int, ...) = NULL;
    if (!r) r = dlsym(RTLD_NEXT, "openat");
    p = REWRITE(p);
    if (flags & O_CREAT) { va_list a; va_start(a, flags); mode_t m = va_arg(a, mode_t); va_end(a); return r(d, p, flags, m); }
    return r(d, p, flags);
}
FILE *fopen(const char *p, const char *m) {
    static FILE *(*r)(const char *, const char *) = NULL;
    if (!r) r = dlsym(RTLD_NEXT, "fopen"); return r(REWRITE(p), m);
}
FILE *fopen64(const char *p, const char *m) {
    static FILE *(*r)(const char *, const char *) = NULL;
    if (!r) r = dlsym(RTLD_NEXT, "fopen64"); return r(REWRITE(p), m);
}
EOF
gcc -O2 -fPIC -shared "$PHOTON_DIR/cmdline-fixup.c" -ldl \
    -o "$PHOTON_DIR/cmdline-fixup.so"

# Per-target cat path (toybox cat on Photon vs GNU cat on Ubuntu/RHEL).
case "$OS_NAME" in
    photon)  CAT_BIN="/usr/bin/toybox cat" ;;
    *)       CAT_BIN="/bin/cat" ;;
esac

cat > "$PHOTON_DIR/Dockerfile" <<EOF
# syntax=docker/dockerfile:1.4
FROM projects.packages.broadcom.com/vsphere/iaas/kubernetes-release/${VKR_K8S_VERSION}/vkr-artifact-server:${VKR_TAG} AS src
FROM ${OS_BASE_IMAGE}

# 1. Pre-extract cri-containerd.tar -> /etc/systemd/system/containerd.service + binaries
RUN --mount=from=src,target=/mnt-src,readonly \\
    tar -xf /mnt-src/data/artifacts/${VKR_INNER_VERSION}/bin/linux/${ARCH}/cri-containerd.tar -C /

# 2. Copy K8s binaries (baker hardcodes /usr/bin/{kubectl,...} in some steps)
RUN --mount=from=src,target=/mnt-src,readonly \\
    cp /mnt-src/data/artifacts/${VKR_INNER_VERSION}/bin/linux/${ARCH}/registry /usr/local/bin/registry && \\
    cp /mnt-src/data/artifacts/${VKR_INNER_VERSION}/bin/linux/${ARCH}/kubelet  /usr/local/bin/kubelet  && \\
    cp /mnt-src/data/artifacts/${VKR_INNER_VERSION}/bin/linux/${ARCH}/kubectl  /usr/local/bin/kubectl  && \\
    cp /mnt-src/data/artifacts/${VKR_INNER_VERSION}/bin/linux/${ARCH}/kubeadm  /usr/local/bin/kubeadm  && \\
    chmod +x /usr/local/bin/registry /usr/local/bin/kubelet /usr/local/bin/kubectl /usr/local/bin/kubeadm && \\
    ln -sf /usr/local/bin/kubectl /usr/bin/kubectl && \\
    ln -sf /usr/local/bin/kubelet /usr/bin/kubelet && \\
    ln -sf /usr/local/bin/kubeadm /usr/bin/kubeadm && \\
    ln -sf /usr/local/bin/registry /usr/bin/registry

# 3. Stub registry.service
RUN mkdir -p /etc/docker/registry /var/lib/registry && \\
    printf '%s\\n' \\
      'version: 0.1' 'log:' '  level: info' \\
      'storage:' '  filesystem:' '    rootdirectory: /var/lib/registry' \\
      'http:' '  addr: :5000' \\
      > /etc/docker/registry/config.yml && \\
    printf '%s\\n' \\
      '[Unit]' 'Description=Docker Registry v2' 'After=network.target' '' \\
      '[Service]' 'ExecStart=/usr/local/bin/registry serve /etc/docker/registry/config.yml' \\
      'Restart=on-failure' '' \\
      '[Install]' 'WantedBy=multi-user.target' \\
      > /etc/systemd/system/registry.service

# 4. Stub kubelet.service
RUN mkdir -p /etc/systemd/system/kubelet.service.d && \\
    printf '%s\\n' \\
      '[Unit]' 'Description=kubelet: The Kubernetes Node Agent' \\
      'Documentation=https://kubernetes.io/docs/' \\
      'Wants=network-online.target' 'After=network-online.target' '' \\
      '[Service]' 'ExecStart=/usr/local/bin/kubelet' \\
      'Restart=always' 'StartLimitInterval=0' 'RestartSec=10' '' \\
      '[Install]' 'WantedBy=multi-user.target' \\
      > /etc/systemd/system/kubelet.service

# 5. WSL host fix: LD_PRELOAD shim that sanitises /proc/cmdline.
#    Use POSIX 'tr' rather than bash's \${var//pat/} — Ubuntu's /bin/sh is
#    dash and doesn't support parameter substitution.
COPY cmdline-fixup.so /usr/local/lib/cmdline-fixup.so
RUN ${CAT_BIN} /proc/cmdline | tr -d '\\\\' > /etc/cmdline-sanitized && \\
    echo '/usr/local/lib/cmdline-fixup.so' > /etc/ld.so.preload
EOF

sudo buildctl --addr unix:///run/buildkit/buildkitd.sock build \
    --frontend dockerfile.v0 \
    --local context="$PHOTON_DIR" \
    --local dockerfile="$PHOTON_DIR" \
    --output "type=image,name=${OS_BASE_REPO}:${OS_VERSION},push=true,registry.insecure=true"
rm -rf "$PHOTON_DIR"

# =============================================================================
step "[8/10] Bake config: ${WORKDIR}/${OS_NAME}-bpf.yaml"
# =============================================================================
CONFIG="${WORKDIR}/${OS_NAME}-bpf.yaml"
cat > "$CONFIG" <<EOF
apiVersion: imageconfiguration.vmware.com/v1alpha1
kind: Image
metadata:
  name: ${IMAGE_NAME}
spec:
  osSpec:
    name: ${OS_NAME}
    version: "${OS_VERSION}"
    image: ${OS_BASE_REPO}:${OS_VERSION}
  kubernetesSpec:
    image: ${WRAPPER_REPO}:${VKR_K8S_VERSION}
  kernelParameters:
    - name: lsm
      value: lockdown,capability,landlock,yama,apparmor,bpf
EOF
info "wrote $CONFIG"

# Persist the same kernelParameters list as KERNEL_PARAMS_LIST for the post-bake
# patcher (a single string of space-separated key=value tokens).
KERNEL_PARAMS_LIST="${KERNEL_PARAMS_LIST:-lsm=lockdown,capability,landlock,yama,apparmor,bpf}"

# =============================================================================
step "[9/12] Bake VMDK"
# =============================================================================
# vcf kr bake produces the VMDK successfully; its built-in 'Generating OVA
# package' step is broken in v3.6.2 standalone mode (compares OSImage name
# against an output-prefixed path). We let the bake fail at that step and
# assemble the OVA ourselves in step [11].
#
# Bake locally first (fast disk), then in step [12] copy the bundle to
# ARTIFACTS_DIR — important when ARTIFACTS_DIR is on a slow filesystem
# (WSL 9P, NFS, SMB).
LOCAL_ARTIFACTS_DIR="${LOCAL_ARTIFACTS_DIR:-${WORKDIR}/.bake-artifacts}"
mkdir -p "$LOCAL_ARTIFACTS_DIR" "$ARTIFACTS_DIR"
ART_DIR="${LOCAL_ARTIFACTS_DIR}/${IMAGE_NAME}"
FINAL_DIR="${ARTIFACTS_DIR}/${IMAGE_NAME}"
rmdir "${WORKDIR}/tmp-dir-metadata" 2>/dev/null || true

set +e
(cd "$WORKDIR" && vcf kr bake -f "$CONFIG" \
    -o "$LOCAL_ARTIFACTS_DIR" \
    --log-level INFO --log-format plain) \
    | tee "${WORKDIR}/bake.log" | tail -20
set -e

[ -s "${ART_DIR}/${IMAGE_NAME}-disk1.vmdk" ] \
    || die "VMDK was not produced; see ${WORKDIR}/bake.log"

# =============================================================================
step "[10/12] Post-bake disk repair (Photon-only): patch /boot/photon.cfg"
# =============================================================================
# ROOT-CAUSE FIX: vcf kr bake's `kernelParameters` writes /etc/default/grub but
# Photon's GRUB reads /boot/photon.cfg, which the bake only patches for two
# baseline knobs (apparmor=1, transparent_hugepage=madvise). Our custom params
# (e.g. lsm=...) never reach the boot cmdline. We mount the produced VMDK's
# boot partition and append each entry to photon_cmdline ourselves.
#
# Defensive: also rewrite /boot/grub2/grub.cfg if a previous failed bake left
# it empty (we observed this in the wild when grub.go's bash wrapper aborted
# under set -u before the heredoc ran).
if [ "$OS_NAME" = "photon" ]; then
    RAW="${WORKDIR}/.bake-repair-disk.raw"
    rm -f "$RAW"
    qemu-img convert -O raw "${ART_DIR}/${IMAGE_NAME}-disk1.vmdk" "$RAW"

    REPAIR_LOOP=$(sudo losetup -fP --show "$RAW")
    BOOT_DEV="${REPAIR_LOOP}p2"
    ROOT_DEV="${REPAIR_LOOP}p3"
    REPAIR_BOOT_MNT="$(mktemp -d)"
    sudo mount "$BOOT_DEV" "$REPAIR_BOOT_MNT"

    # 1. Append every $KERNEL_PARAMS_LIST entry to photon_cmdline (idempotent)
    for param in $KERNEL_PARAMS_LIST; do
        key="${param%%=*}"
        if grep -q "^photon_cmdline=.* ${key}=" "$REPAIR_BOOT_MNT/photon.cfg"; then
            info "kernel param ${key}= already present in photon.cfg"
            continue
        fi
        info "adding ${param} to photon.cfg"
        sudo sed -i -r "s|^(photon_cmdline=.*)\$|\\1 ${param}|" \
            "$REPAIR_BOOT_MNT/photon.cfg"
    done

    # 2. Defensive: if grub.cfg is empty (failed grub.go), regenerate from PARTUUIDs.
    if [ ! -s "$REPAIR_BOOT_MNT/grub2/grub.cfg" ]; then
        warn "grub.cfg was empty — regenerating from PARTUUIDs"
        ROOT_PARTUUID=$(sudo blkid -s PARTUUID -o value "$ROOT_DEV")
        sudo tee "$REPAIR_BOOT_MNT/grub2/grub.cfg" > /dev/null <<GRUB
# Regenerated by setup-image-baker.sh — bake left this empty
set default=0
set timeout=5
loadfont ascii
insmod gfxterm
insmod vbe
insmod tga
insmod png
insmod ext2
insmod part_gpt
set gfxmode="640x480"
gfxpayload=keep
terminal_output gfxterm
set theme=/grub2/themes/photon/theme.txt
load_env -f /photon.cfg
if [ -f /systemd.cfg ]; then
  load_env -f /systemd.cfg
else
  set systemd_cmdline=net.ifnames=0
fi
set rootpartition=PARTUUID=${ROOT_PARTUUID}
menuentry "Photon" {
  linux /\$photon_linux root=\$rootpartition \$photon_cmdline \$systemd_cmdline audit=1
  if [ -f /\$photon_initrd ]; then
    initrd /\$photon_initrd
  fi
}
GRUB
        sudo chmod 600 "$REPAIR_BOOT_MNT/grub2/grub.cfg"
    fi

    sync
    sudo umount "$REPAIR_BOOT_MNT"
    rmdir "$REPAIR_BOOT_MNT"
    sudo losetup -d "$REPAIR_LOOP"

    # 3. Re-pack the patched disk back to streamOptimized VMDK.
    # IMPORTANT: ESXi's import is strict about the streamOptimized layout.
    # qemu-img's `subformat=streamOptimized` is *not* byte-compatible with
    # VMware's vmdk-convert output, and ESXi surfaces that as a misleading
    # "SHA digest does not match manifest" error during deploy. We therefore
    # round-trip through an intermediate VMDK and run open-vmdk's
    # `vmdk-convert` (which writes VMware-canonical streamOptimized).
    rm -f "${ART_DIR}/${IMAGE_NAME}-disk1.vmdk"
    INTERMEDIATE="${WORKDIR}/.bake-repair-intermediate.vmdk"
    qemu-img convert -O vmdk -o subformat=streamOptimized "$RAW" "$INTERMEDIATE"
    rm -f "$RAW"
    vmdk-convert "$INTERMEDIATE" "${ART_DIR}/${IMAGE_NAME}-disk1.vmdk"
    rm -f "$INTERMEDIATE"
fi

# =============================================================================
step "[11/12] Assemble OVA"
# =============================================================================
# HW version selects the OVF template AND the manifest hash algorithm:
#   HW ≤ 12 → SHA1, HW 13-14 → SHA256, HW > 14 → SHA512.
# Default to HW14 (SHA256) for the broadest vSphere/ESXi import compatibility.
# Override via OVA_HW_VERSION (e.g. =15 for HW15+SHA512, =13 for older targets).
OVA_HW_VERSION="${OVA_HW_VERSION:-14}"
(cd "$ART_DIR" && \
 /usr/bin/mkova.sh -f efi --hw "$OVA_HW_VERSION" "$IMAGE_NAME" "${IMAGE_NAME}-disk1.vmdk")

# =============================================================================
step "[12/12] Publish to ARTIFACTS_DIR"
# =============================================================================
# Copy the bundle (OVA + per-bake metadata) from the fast local working dir
# to ARTIFACTS_DIR. If they are the same path, this is a no-op.
if [ "$(realpath "$LOCAL_ARTIFACTS_DIR")" != "$(realpath "$ARTIFACTS_DIR")" ]; then
    mkdir -p "$FINAL_DIR"
    cp -f "$ART_DIR"/* "$FINAL_DIR/"
fi

echo "OVA:  ${FINAL_DIR}/${IMAGE_NAME}.ova"
ls -lh "${FINAL_DIR}/${IMAGE_NAME}.ova"
echo
echo "Next: scan with"
echo "    OS_TARGET=${OS_TARGET} ./scan-baked-ova.sh \\"
echo "        ${FINAL_DIR}/${IMAGE_NAME}.ova ${IMAGE_NAME}"
