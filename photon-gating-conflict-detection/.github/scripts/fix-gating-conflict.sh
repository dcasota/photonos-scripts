#!/usr/bin/env bash
#
# fix-gating-conflict.sh
#
# Surgical workaround for Photon OS build-time package gating conflicts.
#
# When photon-subrelease <= 91, the old monolithic spec (e.g. libcap 2.66 in
# SPECS/91/) is active, but the remote packages repo already ships the new split
# version (e.g. libcap-libs 2.77) which declares "Conflicts: libcap < 2.77-1".
# The tdnf solver in the build sandbox cannot reconcile the two, breaking every
# package whose toolchain install pulls in the conflicting package.
#
# This script fixes the conflict by:
#   1. Swapping the build_if guards so the NEW spec (>= 92) becomes active at
#      the current subrelease, and the OLD spec (<= 91) becomes inactive.
#   2. Optionally building the package via the Photon build system so the local
#      repo gets the new RPMs before the main build runs.
#   3. Updating the local RPM repo metadata.
#
# Usage:
#   fix-gating-conflict.sh [OPTIONS]
#
# Options:
#   -p, --package NAME       Package to fix (default: libcap)
#   -b, --build-root PATH    Release branch root (default: $HOME/5.0)
#   -s, --subrelease NUM     Current photon-subrelease value (default: read from
#                             build-config.json)
#   -B, --build              Also build the package after patching specs
#   -n, --dry-run            Show what would be changed without modifying files
#   -r, --revert             Undo previous spec guard changes (restore backups)
#   -h, --help               Show this help message
#
# Examples:
#   # Preview changes for libcap
#   fix-gating-conflict.sh --dry-run
#
#   # Patch specs and build libcap
#   fix-gating-conflict.sh --build
#
#   # Fix a different package with a custom build root
#   fix-gating-conflict.sh -p tdnf -b /root/5.0 --build
#
#   # Revert all changes
#   fix-gating-conflict.sh --revert

set -euo pipefail

# ---------- defaults ----------
PACKAGE="libcap"
BUILD_ROOT="${HOME}/5.0"
SUBRELEASE=""
DO_BUILD=false
DRY_RUN=false
REVERT=false

# ---------- colors (disabled if not a terminal) ----------
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { error "$@"; exit 1; }
banner() { echo -e "\n${CYAN}${BOLD}=== $* ===${NC}\n"; }

# ---------- usage ----------
usage() {
    sed -n '/^# Usage:/,/^[^#]/{ /^[^#]/d; s/^# \?//p; }' "$0"
    exit 0
}

# ---------- argument parsing ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--package)    PACKAGE="$2";    shift 2 ;;
        -b|--build-root) BUILD_ROOT="$2"; shift 2 ;;
        -s|--subrelease) SUBRELEASE="$2"; shift 2 ;;
        -B|--build)      DO_BUILD=true;   shift   ;;
        -n|--dry-run)    DRY_RUN=true;    shift   ;;
        -r|--revert)     REVERT=true;     shift   ;;
        -h|--help)       usage                    ;;
        *) die "Unknown option: $1. Use --help for usage." ;;
    esac
done

# ---------- resolve paths ----------
BUILD_ROOT="$(realpath "$BUILD_ROOT")"
BUILD_CONFIG="${BUILD_ROOT}/build-config.json"
COMMON_DIR="$(realpath "${BUILD_ROOT}/../common" 2>/dev/null || true)"

[[ -f "$BUILD_CONFIG" ]] || die "build-config.json not found at ${BUILD_CONFIG}"

# Resolve common-branch-path from build-config.json if default doesn't exist
if [[ ! -d "$COMMON_DIR" ]]; then
    _rel=$(python3 -c "import json; print(json.load(open('${BUILD_CONFIG}'))['common-branch-path'])" 2>/dev/null || echo "")
    if [[ -n "$_rel" ]]; then
        COMMON_DIR="$(realpath "${BUILD_ROOT}/${_rel}")"
    fi
fi
[[ -d "$COMMON_DIR" ]] || die "Common directory not found. Expected at ${COMMON_DIR}"

SPECS_RELEASE="${BUILD_ROOT}/SPECS"
SPECS_PHOTON="${COMMON_DIR}/SPECS"
STAGE_RPMS="${BUILD_ROOT}/stage/RPMS"
PKG_PREQ="${BUILD_ROOT}/data/builder-pkg-preq.json"

# ---------- read subrelease ----------
if [[ -z "$SUBRELEASE" ]]; then
    SUBRELEASE=$(python3 -c "
import json
cfg = json.load(open('${BUILD_CONFIG}'))
print(cfg['photon-build-param']['photon-subrelease'])
" 2>/dev/null) || die "Cannot read photon-subrelease from ${BUILD_CONFIG}"
fi
info "Package:          ${PACKAGE}"
info "Build root:       ${BUILD_ROOT}"
info "Common dir:       ${COMMON_DIR}"
info "Subrelease:       ${SUBRELEASE}"
info "Dry run:          ${DRY_RUN}"
info "Build after fix:  ${DO_BUILD}"

# ---------- locate spec files ----------
banner "Locating spec files for '${PACKAGE}'"

NEW_SPEC=""  # the >= 92 spec (the one we want active)
OLD_SPEC=""  # the <= 91 spec (the one we want inactive)

find_specs() {
    local base="$1"
    local pkg="$2"

    # New spec: directly under SPECS/<package>/
    local candidate="${base}/${pkg}/${pkg}.spec"
    if [[ -f "$candidate" ]]; then
        local guard
        guard=$(head -5 "$candidate" | sed -n 's/^%global[[:space:]]\+build_if[[:space:]]\+//p' || true)
        if [[ "$guard" == *">="* ]]; then
            NEW_SPEC="$candidate"
        elif [[ "$guard" == *"<="* ]]; then
            OLD_SPEC="$candidate"
        fi
    fi

    # Old spec: under SPECS/91/<package>/ (subrelease-gated)
    candidate="${base}/91/${pkg}/${pkg}.spec"
    if [[ -f "$candidate" ]]; then
        local guard
        guard=$(head -5 "$candidate" | sed -n 's/^%global[[:space:]]\+build_if[[:space:]]\+//p' || true)
        if [[ "$guard" == *"<="* ]]; then
            OLD_SPEC="$candidate"
        elif [[ "$guard" == *">="* ]]; then
            NEW_SPEC="$candidate"
        fi
    fi
}

find_specs "$SPECS_RELEASE" "$PACKAGE"
# If we haven't found both, also check the photon (common) SPECS
if [[ -z "$NEW_SPEC" ]] || [[ -z "$OLD_SPEC" ]]; then
    find_specs "$SPECS_PHOTON" "$PACKAGE"
fi

[[ -n "$NEW_SPEC" ]] || die "Cannot find the NEW spec (>= 92 guard) for '${PACKAGE}'"
[[ -n "$OLD_SPEC" ]] || die "Cannot find the OLD spec (<= 91 guard) for '${PACKAGE}'"

info "New spec (to activate):    ${NEW_SPEC}"
info "Old spec (to deactivate):  ${OLD_SPEC}"

# ---------- extract version info ----------
NEW_VERSION=$(grep -m1 '^Version:' "$NEW_SPEC" | awk '{print $2}')
NEW_RELEASE=$(grep -m1 '^Release:' "$NEW_SPEC" | awk '{print $2}')
OLD_VERSION=$(grep -m1 '^Version:' "$OLD_SPEC" | awk '{print $2}')
OLD_RELEASE=$(grep -m1 '^Release:' "$OLD_SPEC" | awk '{print $2}')

info "New version: ${NEW_VERSION}-${NEW_RELEASE}"
info "Old version: ${OLD_VERSION}-${OLD_RELEASE}"

# ---------- extract sub-package names from new spec ----------
banner "Analyzing new spec sub-packages"

NEW_SUBPKGS=()
while IFS= read -r line; do
    subpkg=$(echo "$line" | sed -n 's/^%package[[:space:]]\+//p')
    if [[ -n "$subpkg" ]]; then
        # Skip flags like -n, -l
        if [[ "$subpkg" == -* ]]; then
            subpkg=$(echo "$subpkg" | awk '{print $2}')
        fi
        # Expand %{name}-<subpkg> pattern
        if [[ "$subpkg" != *"%"* ]]; then
            NEW_SUBPKGS+=("${PACKAGE}-${subpkg}")
        fi
    fi
done < "$NEW_SPEC"

info "Sub-packages in new spec: ${PACKAGE} ${NEW_SUBPKGS[*]:-none}"

# ---------- check current staged RPMs ----------
banner "Checking currently staged RPMs"

ARCH=$(uname -m)
STAGED_DIR="${STAGE_RPMS}/${ARCH}"
STAGED_NOARCH="${STAGE_RPMS}/noarch"

if [[ -d "$STAGED_DIR" ]]; then
    mapfile -t OLD_RPMS < <(find "$STAGED_DIR" "$STAGED_NOARCH" -name "${PACKAGE}-*.ph5.*.rpm" 2>/dev/null | sort)
    if [[ ${#OLD_RPMS[@]} -gt 0 ]]; then
        info "Found ${#OLD_RPMS[@]} existing staged RPM(s):"
        for rpm in "${OLD_RPMS[@]}"; do
            echo "    $(basename "$rpm")"
        done
    else
        info "No existing staged RPMs found for ${PACKAGE}"
    fi
else
    warn "Stage RPMS directory not found at ${STAGED_DIR}"
fi

# ---------- revert mode ----------
if $REVERT; then
    banner "Reverting spec changes"
    reverted=0
    for spec in "$NEW_SPEC" "$OLD_SPEC"; do
        if [[ -f "${spec}.bak" ]]; then
            if $DRY_RUN; then
                info "[dry-run] Would restore ${spec} from ${spec}.bak"
            else
                cp "${spec}.bak" "$spec"
                info "Restored ${spec}"
            fi
            ((reverted++))
        else
            warn "No backup found for ${spec}"
        fi
    done
    if [[ -f "${PKG_PREQ}.bak" ]]; then
        if $DRY_RUN; then
            info "[dry-run] Would restore ${PKG_PREQ} from ${PKG_PREQ}.bak"
        else
            cp "${PKG_PREQ}.bak" "$PKG_PREQ"
            info "Restored ${PKG_PREQ}"
        fi
        ((reverted++))
    fi
    if [[ $reverted -eq 0 ]]; then
        warn "Nothing to revert -- no .bak files found"
    else
        info "Reverted ${reverted} file(s)"
    fi
    exit 0
fi

# ---------- swap build_if guards ----------
banner "Patching spec build_if guards"

patch_build_if() {
    local spec_file="$1"
    local new_guard="$2"
    local label="$3"

    local current_guard
    current_guard=$(head -5 "$spec_file" | grep '%global.*build_if' || true)

    if [[ -z "$current_guard" ]]; then
        warn "No build_if found in ${spec_file} -- skipping"
        return
    fi

    info "${label}: ${current_guard}  -->  ${new_guard}"

    if $DRY_RUN; then
        info "[dry-run] Would patch ${spec_file}"
        return
    fi

    # Backup original
    if [[ ! -f "${spec_file}.bak" ]]; then
        cp "$spec_file" "${spec_file}.bak"
        info "Backup created: ${spec_file}.bak"
    fi

    # Replace the build_if line
    sed -i "1,5 s|^%global[[:space:]]\+build_if[[:space:]]\+.*|${new_guard}|" "$spec_file"
}

# The new spec currently says >= 92; change it to >= <subrelease> so it
# becomes active at the current subrelease.
NEW_GUARD="%global build_if %{photon_subrelease} >= ${SUBRELEASE}"
# The old spec currently says <= 91; change it to <= <subrelease-1> so it
# becomes inactive at the current subrelease.
OLD_THRESHOLD=$(( SUBRELEASE - 1 ))
OLD_GUARD="%global build_if %{photon_subrelease} <= ${OLD_THRESHOLD}"

patch_build_if "$NEW_SPEC" "$NEW_GUARD" "Activate new spec"
patch_build_if "$OLD_SPEC" "$OLD_GUARD" "Deactivate old spec"

# ---------- update builder-pkg-preq.json if needed ----------
banner "Checking toolchain RPM install list"

# For the libcap split, the new spec produces libcap-libs (the shared library)
# as a sub-package. The toolchain list installs "libcap" which in the new spec
# has Requires: libcap-libs, so tdnf should pull it transitively. But it's
# safer to verify and warn.
if [[ -f "$PKG_PREQ" ]]; then
    # Check if any new sub-packages should be added to listToolChainRPMsToInstall
    PREQ_HAS_PKG=$(python3 -c "
import json
data = json.load(open('${PKG_PREQ}'))
rpms = data.get('listToolChainRPMsToInstall', [])
print('yes' if '${PACKAGE}' in rpms else 'no')
" 2>/dev/null)

    if [[ "$PREQ_HAS_PKG" == "yes" ]]; then
        info "'${PACKAGE}' is in listToolChainRPMsToInstall"
        # Check if key sub-packages (like libcap-libs) need explicit addition
        for subpkg in "${NEW_SUBPKGS[@]}"; do
            # Only consider *-libs sub-packages as critical for toolchain
            # (these contain shared libraries that other packages link against)
            if [[ "$subpkg" != *-libs ]]; then
                continue
            fi
            is_present=$(python3 -c "
import json
data = json.load(open('${PKG_PREQ}'))
rpms = data.get('listToolChainRPMsToInstall', [])
print('yes' if '${subpkg}' in rpms else 'no')
" 2>/dev/null)
            if [[ "$is_present" == "no" ]]; then
                info "Sub-package '${subpkg}' is NOT in listToolChainRPMsToInstall"
                info "  The main '${PACKAGE}' package requires it, so tdnf should"
                info "  pull it transitively. Adding it explicitly for safety."
                if $DRY_RUN; then
                    info "[dry-run] Would add '${subpkg}' to ${PKG_PREQ}"
                else
                    if [[ ! -f "${PKG_PREQ}.bak" ]]; then
                        cp "$PKG_PREQ" "${PKG_PREQ}.bak"
                        info "Backup created: ${PKG_PREQ}.bak"
                    fi
                    python3 -c "
import json

with open('${PKG_PREQ}', 'r') as f:
    data = json.load(f)

rpms = data.get('listToolChainRPMsToInstall', [])

# Insert after '${PACKAGE}' for readability
try:
    idx = rpms.index('${PACKAGE}')
    rpms.insert(idx + 1, '${subpkg}')
except ValueError:
    rpms.append('${subpkg}')

data['listToolChainRPMsToInstall'] = rpms

with open('${PKG_PREQ}', 'w') as f:
    json.dump(data, f, indent=4)
    f.write('\n')
"
                    info "Added '${subpkg}' to listToolChainRPMsToInstall"
                fi
            else
                info "Sub-package '${subpkg}' already in listToolChainRPMsToInstall"
            fi
        done
    else
        info "'${PACKAGE}' is not in listToolChainRPMsToInstall -- no changes needed"
    fi
else
    warn "builder-pkg-preq.json not found at ${PKG_PREQ}"
fi

# ---------- remove stale staged RPMs ----------
banner "Removing stale staged RPMs for ${PACKAGE}"

if [[ -d "$STAGED_DIR" ]]; then
    mapfile -t STALE_RPMS < <(find "$STAGED_DIR" "$STAGED_NOARCH" \
        -name "${PACKAGE}-*.ph5.*.rpm" 2>/dev/null | sort)
    for rpm in "${STALE_RPMS[@]}"; do
        rpmbase="$(basename "$rpm")"
        # Only remove RPMs from the old version
        if [[ "$rpmbase" == *"${OLD_VERSION}"* ]]; then
            if $DRY_RUN; then
                info "[dry-run] Would remove stale RPM: ${rpm}"
            else
                rm -f "$rpm"
                info "Removed stale RPM: ${rpmbase}"
            fi
        fi
    done
fi

# ---------- update repo metadata ----------
if ! $DRY_RUN && [[ -d "$STAGE_RPMS" ]]; then
    banner "Updating local RPM repo metadata"
    if command -v createrepo_c &>/dev/null; then
        createrepo_c --update --workers="$(nproc)" --skip-stat \
            --no-database --general-compress-type=gz "$STAGE_RPMS"
        info "Repo metadata updated"
    elif command -v createrepo &>/dev/null; then
        createrepo --update "$STAGE_RPMS"
        info "Repo metadata updated"
    else
        warn "createrepo/createrepo_c not found -- skipping repo metadata update"
    fi
fi

# ---------- build the package ----------
if $DO_BUILD; then
    banner "Building ${PACKAGE} via Photon build system"

    if $DRY_RUN; then
        info "[dry-run] Would run: make -C ${BUILD_ROOT} pkgs=${PACKAGE}"
    else
        info "Running: make -C ${BUILD_ROOT} pkgs=${PACKAGE}"
        if make -C "$BUILD_ROOT" "pkgs=${PACKAGE}"; then
            info "Build succeeded"

            # Verify new RPMs are staged
            banner "Verifying staged RPMs"
            mapfile -t BUILT_RPMS < <(find "$STAGED_DIR" "$STAGED_NOARCH" \
                -name "${PACKAGE}-*${NEW_VERSION}*.ph5.*.rpm" 2>/dev/null | sort)
            if [[ ${#BUILT_RPMS[@]} -gt 0 ]]; then
                info "New staged RPMs (${#BUILT_RPMS[@]}):"
                for rpm in "${BUILT_RPMS[@]}"; do
                    echo "    $(basename "$rpm")"
                done
            else
                warn "No new RPMs found for ${PACKAGE} ${NEW_VERSION} in stage"
                warn "The build may have determined RPMs already existed"
            fi
        else
            error "Build failed. Check logs at ${BUILD_ROOT}/stage/LOGS/${PACKAGE}*/"
            error "You can re-run the main build after investigating."
            exit 1
        fi
    fi
fi

# ---------- summary ----------
banner "Summary"

if $DRY_RUN; then
    info "Dry-run complete. No files were modified."
    info "Re-run without --dry-run to apply changes."
else
    info "Spec guards patched successfully."
    echo ""
    echo -e "  ${BOLD}New spec${NC} (now active at subrelease ${SUBRELEASE}):"
    echo "    ${NEW_SPEC}"
    head -1 "$NEW_SPEC" | sed 's/^/    /'
    echo ""
    echo -e "  ${BOLD}Old spec${NC} (now inactive at subrelease ${SUBRELEASE}):"
    echo "    ${OLD_SPEC}"
    head -1 "$OLD_SPEC" | sed 's/^/    /'
    echo ""

    if ! $DO_BUILD; then
        info "Specs are patched but ${PACKAGE} has NOT been rebuilt yet."
        info "You can now either:"
        echo "    1. Build just ${PACKAGE}:  make -C ${BUILD_ROOT} pkgs=${PACKAGE}"
        echo "    2. Run the full ISO build: make -C ${BUILD_ROOT} image IMG_NAME=iso"
        echo "       (${PACKAGE} will be built automatically as part of the toolchain)"
        echo ""
    fi

    info "To revert all changes:  $0 -p ${PACKAGE} -b ${BUILD_ROOT} --revert"
fi
