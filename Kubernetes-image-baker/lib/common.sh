#!/bin/bash
# =============================================================================
# common.sh — shared library for VKR image-baking scripts
#
# Sourced by setup-image-baker.sh and scan-baked-ova.sh.
# All version pins, OS-target switches, and helper functions live here so the
# rest of the scripts have no embedded hardcoded versions.
#
# Override any value via env, e.g.
#     OS_TARGET=ubuntu VKR_K8S_VERSION=1.32.7 ./setup-image-baker.sh
# =============================================================================

# ---------------- Version pins (single source of truth) ----------------------
BUILDKIT_VERSION="${BUILDKIT_VERSION:-v0.15.0}"
VCF_VERSION="${VCF_VERSION:-v9.0.2}"
KR_PLUGIN_VERSION="${KR_PLUGIN_VERSION:-v3.6.2}"
PHOTON_VERSION="${PHOTON_VERSION:-5.0}"           # used by scanner

# VKR (Kubernetes release) version; affects which artifact-server image is
# pulled and which OSImage YAML is selected. Run `vcf kr get -a` for catalog.
VKR_K8S_VERSION="${VKR_K8S_VERSION:-1.32.10}"
VKR_TAG="${VKR_TAG:-v1.32.10_vmware.1-fips-vkr.2}"
VKR_INNER_VERSION="${VKR_INNER_VERSION:-v1.32.10+vmware.1-fips}"

# ---------------- OS target switch -------------------------------------------
# Selects which OSImage to bake. The setup script builds a per-target custom
# base image (with cri-containerd extracted, kubelet/registry stubs, etc.).
# Supported: photon | ubuntu | rhel.
OS_TARGET="${OS_TARGET:-photon}"

# Per-target defaults. Override by exporting before running.
case "$OS_TARGET" in
    photon)
        OS_NAME_DEFAULT=photon
        OS_VERSION_DEFAULT="5"
        OS_BASE_IMAGE_DEFAULT="photon:5.0"
        ;;
    ubuntu)
        OS_NAME_DEFAULT=ubuntu
        OS_VERSION_DEFAULT="22.04"
        OS_BASE_IMAGE_DEFAULT="ubuntu:22.04"
        ;;
    rhel)
        OS_NAME_DEFAULT=rhel
        OS_VERSION_DEFAULT="9"
        OS_BASE_IMAGE_DEFAULT="registry.access.redhat.com/ubi9/ubi:latest"
        ;;
    *)
        echo "ERROR: OS_TARGET must be one of: photon, ubuntu, rhel (got '$OS_TARGET')" >&2
        return 1 2>/dev/null || exit 1
        ;;
esac

OS_NAME="${OS_NAME:-$OS_NAME_DEFAULT}"
OS_VERSION="${OS_VERSION:-$OS_VERSION_DEFAULT}"
OS_BASE_IMAGE="${OS_BASE_IMAGE:-$OS_BASE_IMAGE_DEFAULT}"
ARCH="${ARCH:-amd64}"

# ---------------- Paths and registry -----------------------------------------
WORKDIR="${WORKDIR:-$HOME}"
REGISTRY_PORT="${REGISTRY_PORT:-5000}"
REGISTRY_HOST="${REGISTRY_HOST:-localhost}"
REGISTRY="${REGISTRY:-${REGISTRY_HOST}:${REGISTRY_PORT}}"
WRAPPER_REPO="${WRAPPER_REPO:-${REGISTRY}/vkr-wrapper}"
OS_BASE_REPO="${OS_BASE_REPO:-${REGISTRY}/${OS_NAME}-with-containerd}"

# Output naming follows the VKR convention so the bake's OSImage match works.
IMAGE_NAME="${IMAGE_NAME:-${OS_NAME}-${OS_VERSION//./}-${ARCH}-vmi-k8s-v${VKR_K8S_VERSION}---vmware.1-fips-vkr.2}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${WORKDIR}/artifacts}"

# ---------------- Scanner thresholds (used by scan-baked-ova.sh) -------------
GRYPE_FAIL_ON="${GRYPE_FAIL_ON:-high}"           # negligible|low|medium|high|critical
STIG_FAIL_ON_HIGH="${STIG_FAIL_ON_HIGH:-1}"
STIG_REPO_REF="${STIG_REPO_REF:-master}"
SKIP_STIG="${SKIP_STIG:-0}"

# ---------------- Helpers ----------------------------------------------------
step()    { echo; echo "=== $* ==="; }
info()    { echo "[info] $*"; }
warn()    { echo "[warn] $*" >&2; }
die()     { echo "[error] $*" >&2; exit 1; }
need()    { command -v "$1" >/dev/null; }

# detect_pkg_mgr — Photon=tdnf, Fedora/RHEL=dnf, Ubuntu/Debian=apt-get
detect_pkg_mgr() {
    if   need tdnf;    then echo "tdnf"
    elif need dnf;     then echo "dnf"
    elif need apt-get; then echo "apt-get"
    else echo "unknown"
    fi
}

PKG_MGR="${PKG_MGR:-$(detect_pkg_mgr)}"

# pkg_install pkg1 pkg2 ... (idempotent, uses sudo when available)
pkg_install() {
    [ "$#" -eq 0 ] && return 0
    local SUDO=""; need sudo && [ "$(id -u)" -ne 0 ] && SUDO=sudo
    case "$PKG_MGR" in
        tdnf|dnf) $SUDO "$PKG_MGR" install -y "$@" ;;
        apt-get)  $SUDO apt-get update -qq && \
                  $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" ;;
        *) die "no supported package manager (tdnf/dnf/apt-get) on this host" ;;
    esac
}

# install_only_if_missing pkg_or_command pkg1 [pkg2 ...]
# If the named command is missing, install pkg1...
install_only_if_missing() {
    local cmd="$1"; shift
    need "$cmd" || pkg_install "$@"
}

# Print every effective tunable (handy for debugging)
dump_config() {
    cat <<EOF
[config] OS_TARGET=$OS_TARGET  OS_NAME=$OS_NAME  OS_VERSION=$OS_VERSION
[config] OS_BASE_IMAGE=$OS_BASE_IMAGE
[config] VKR_K8S_VERSION=$VKR_K8S_VERSION  VKR_TAG=$VKR_TAG
[config] PKG_MGR=$PKG_MGR
[config] BUILDKIT_VERSION=$BUILDKIT_VERSION  VCF_VERSION=$VCF_VERSION
[config] KR_PLUGIN_VERSION=$KR_PLUGIN_VERSION
[config] REGISTRY=$REGISTRY
[config] WRAPPER_REPO=$WRAPPER_REPO
[config] OS_BASE_REPO=$OS_BASE_REPO
[config] IMAGE_NAME=$IMAGE_NAME
[config] ARTIFACTS_DIR=$ARTIFACTS_DIR
EOF
}
