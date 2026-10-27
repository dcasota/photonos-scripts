#!/usr/bin/env bash
# setup-photon50-aarch64-iso.sh
# Session-derived setup: rustup/cargo through the kernel-spec unlink patch.
# Does NOT run "make minimal-iso" (that step is hours long and comes after this).
#
# Usage:
#   sudo -E bash setup-photon50-aarch64-iso.sh
#   sudo -E bash setup-photon50-aarch64-iso.sh --skip-sharukhan
#   PHOTON_TREE=/root/5.0 COMMON_TREE=/root/common bash setup-photon50-aarch64-iso.sh
set -euo pipefail

PHOTON_TREE="${PHOTON_TREE:-/root/5.0}"
COMMON_TREE="${COMMON_TREE:-/root/common}"
SHARUKHAN_DIR="${SHARUKHAN_DIR:-/root/photonos-scripts/staging/sharukhan-cli}"
SUBRELEASE="${SUBRELEASE:-92}"          # 92 = 6.12 from common; 91 = 5.0's 6.1
MAINLINE="${MAINLINE:-92}"
SKIP_RUST=0
SKIP_SHARUKHAN=0
SKIP_PKGS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-rust) SKIP_RUST=1; shift ;;
    --skip-sharukhan) SKIP_SHARUKHAN=1; shift ;;
    --skip-pkgs) SKIP_PKGS=1; shift ;;
    --subrelease) SUBRELEASE="${2:?}"; shift 2 ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# rustup writes to the invoking user's HOME. Keep that user for cargo.
SETUP_USER="${SUDO_USER:-${USER:-root}}"
if [[ -n "${SUDO_USER:-}" && "$EUID" -eq 0 ]]; then
  SETUP_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
else
  SETUP_HOME="${HOME}"
fi
SETUP_HOME="${SETUP_HOME:-/root}"

log "host=$(uname -m) user=$SETUP_USER home=$SETUP_HOME"
log "PHOTON_TREE=$PHOTON_TREE"
log "COMMON_TREE=$COMMON_TREE"
log "SHARUKHAN_DIR=$SHARUKHAN_DIR"
log "subrelease=$SUBRELEASE mainline=$MAINLINE"

if [[ "$(uname -m)" != "aarch64" ]]; then
  echo "WARNING: this host is $(uname -m). An aarch64 ISO needs an aarch64 builder." >&2
fi

# --------------------------------------------------------------------------
# 1. Host packages (needed for rustc, jq, docker image, contain_unpriv)
# --------------------------------------------------------------------------
if [[ "$SKIP_PKGS" -eq 0 ]]; then
  log "host packages"
  if command -v tdnf >/dev/null 2>&1; then
    tdnf makecache || true
    tdnf install -y git bc gcc make glibc-devel createrepo_c texinfo wget \
      python3-pip tar dosfstools cdrkit rpm-build clang libevent jq docker \
      curl ca-certificates || true
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      git bc build-essential curl ca-certificates python3-pip jq docker.io \
      createrepo-c xorriso rpm wget clang libevent-dev || true
  fi
  python3 -m pip install --upgrade pip setuptools >/dev/null 2>&1 || true
  python3 -m pip install docker pyOpenSSL license_expression pyyaml >/dev/null 2>&1 || true
else
  log "skip host packages"
fi

command -v jq >/dev/null 2>&1 || die "jq is required (Makefile reads build-config.json with it)"
command -v python3 >/dev/null 2>&1 || die "python3 is required"

# --------------------------------------------------------------------------
# 2. rustup / cargo (same user that will run cargo build)
# --------------------------------------------------------------------------
install_rust_as_user() {
  local home="$1"
  export HOME="$home"
  # shellcheck disable=SC1091
  if [[ -f "$home/.cargo/env" ]]; then
    # shellcheck source=/dev/null
    source "$home/.cargo/env"
  fi
  if command -v cargo >/dev/null 2>&1 && command -v rustc >/dev/null 2>&1; then
    rustc --version
    cargo --version
    return 0
  fi
  log "install rustup into $home"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  # shellcheck source=/dev/null
  source "$home/.cargo/env"
  rustc --version
  cargo --version
}

if [[ "$SKIP_RUST" -eq 0 ]]; then
  log "rust toolchain"
  if [[ -n "${SUDO_USER:-}" && "$EUID" -eq 0 ]]; then
    su - "$SUDO_USER" -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
      # shellcheck disable=SC1090
      source "$HOME/.cargo/env"
      rustc --version
      cargo --version' || install_rust_as_user "$SETUP_HOME"
  else
    install_rust_as_user "$SETUP_HOME"
  fi
  if [[ -f "$SETUP_HOME/.cargo/env" ]]; then
    # shellcheck source=/dev/null
    source "$SETUP_HOME/.cargo/env"
  fi
else
  log "skip rust"
fi

# --------------------------------------------------------------------------
# 3. Optional: build sharukhan (not required for stock make iso)
# --------------------------------------------------------------------------
if [[ "$SKIP_SHARUKHAN" -eq 0 && -d "$SHARUKHAN_DIR" ]]; then
  log "cargo build --release sharukhan-cli"
  if [[ -f "$SETUP_HOME/.cargo/env" ]]; then
    # shellcheck source=/dev/null
    source "$SETUP_HOME/.cargo/env"
  fi
  command -v cargo >/dev/null 2>&1 || die "cargo not on PATH after rustup"
  (
    cd "$SHARUKHAN_DIR"
    cargo build --release
    ls -l target/release/sharukhan
  )
  echo "NOTE: sharukhan variant-patches is blocked on stale fix/* branches."
  echo "      Stock ISO path is make -C $PHOTON_TREE minimal-iso — not sharukhan build-iso."
elif [[ "$SKIP_SHARUKHAN" -eq 1 ]]; then
  log "skip sharukhan"
else
  log "sharukhan dir not found ($SHARUKHAN_DIR) — skip"
fi

# --------------------------------------------------------------------------
# 4. Photon 5.0 + common trees
# --------------------------------------------------------------------------
log "photon trees"
[[ -d "$PHOTON_TREE/.git" ]] || die "PHOTON_TREE is not a git checkout: $PHOTON_TREE"
[[ -f "$COMMON_TREE/build.py" ]] || die "COMMON_TREE has no build.py: $COMMON_TREE"
[[ -d "$PHOTON_TREE/SPECS" ]] || die "PHOTON_TREE has no SPECS: $PHOTON_TREE"
mkdir -p "$PHOTON_TREE/stage"

# --------------------------------------------------------------------------
# 5. build-config.json — both layers
#    Makefile jq: top-level common-branch-path, stage-path, photon-path
#    build.py:    photon-build-param.photon-subrelease
# --------------------------------------------------------------------------
log "rewrite build-config.json keys (backup first)"
CONF="$PHOTON_TREE/build-config.json"
[[ -f "$CONF" ]] || die "missing $CONF"
cp -a "$CONF" "$CONF.bak.$(date +%Y%m%d%H%M%S)"

COMMON_RELATIVE="$(realpath --relative-to="$PHOTON_TREE" "$COMMON_TREE")"

python3 - "$CONF" "$PHOTON_TREE" "$COMMON_RELATIVE" "$SUBRELEASE" "$MAINLINE" <<'PY'
import json, sys
path, photon, common_rel, sub, main = sys.argv[1:6]
cfg = json.load(open(path))
p = cfg.setdefault("photon-build-param", {})
p["photon-subrelease"] = sub
p["photon-mainline"] = main
p["photon-release-version"] = p.get("photon-release-version") or "5.0"
p["common-branch-path"] = common_rel
cfg["photon-build-param"] = p
cfg["common-branch-path"] = common_rel
cfg["photon-path"] = photon
cfg["stage-path"] = photon.rstrip("/") + "/stage"
cfg["spec-path"] = cfg.get("spec-path") or ""
cfg["release-branch-path"] = photon
json.dump(cfg, open(path, "w"), indent=2)
json.dump({
    "common-branch-path": cfg["common-branch-path"],
    "photon-path": cfg["photon-path"],
    "stage-path": cfg["stage-path"],
    "release-branch-path": cfg["release-branch-path"],
    "photon-subrelease": p["photon-subrelease"],
    "photon-mainline": p["photon-mainline"],
}, sys.stdout, indent=2)
print()
PY

jq -er '.["common-branch-path"]' "$CONF" | grep -vq '^null$' \
  || die "jq common-branch-path is null"
[[ "$(jq -r '.["stage-path"]' "$CONF")" == "$PHOTON_TREE/stage" ]] \
  || die "stage-path was not written as $PHOTON_TREE/stage"
realpath "$PHOTON_TREE/stage" >/dev/null

# --------------------------------------------------------------------------
# 6. Smallest code fix: unlink(missing_ok=True) in kernel spec generator
# --------------------------------------------------------------------------
GEN="$COMMON_TREE/support/spec-generator/create-kernel-deps-specs-from-template.py"
log "patch kernel spec generator: $GEN"
[[ -f "$GEN" ]] || die "generator missing: $GEN"
if grep -q 'spec_file.unlink(missing_ok=True)' "$GEN"; then
  echo "already patched"
else
  cp -a "$GEN" "$GEN.bak.$(date +%Y%m%d%H%M%S)"
  python3 - "$GEN" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
t = p.read_text()
old = "            spec_file.unlink()"
new = "            spec_file.unlink(missing_ok=True)"
if old not in t:
    raise SystemExit("unlink() line not found — generator changed, patch by hand")
p.write_text(t.replace(old, new, 1))
print("patched unlink() -> unlink(missing_ok=True)")
PY
fi

# optional: drop dangling intel-driver spec symlinks that triggered the bug
if [[ -d "$PHOTON_TREE/SPECS/kernels-drivers-intel" ]]; then
  find "$PHOTON_TREE/SPECS/kernels-drivers-intel" -xtype l -print -delete || true
fi

log "setup complete"
cat <<EOF

Next (not run by this script):

  cd $PHOTON_TREE
  sudo make minimal-iso    # or: sudo make iso

Checks already satisfied:
  - cargo/rustc available for $SETUP_USER (unless --skip-rust)
  - jq can read top-level common-branch-path / stage-path / photon-path
  - photon-subrelease=$SUBRELEASE  photon-mainline=$MAINLINE
  - stage dir $PHOTON_TREE/stage exists
  - kernel spec generator unlinks missing files safely

Still blocked on purpose:
  - sharukhan variant-patches / build-iso --poi 2.8
    (fix/poi-fips-sshd-algorithms and siblings conflict on current 5.0)
EOF
