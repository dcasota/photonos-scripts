#!/bin/sh
#
# Photon OS 5.0 userland + experimental Linux 7.2.7
# wrapper v4 — always rewires common-branch-path before make
#
# $1 BASE_DIR        default /root
# $2 COMMON_BRANCH   default common
# $3 RELEASE_BRANCH  default experimental/linux-7.2.7
# $4 OUTPUT_DIR      default /mnt/c/Users/dcaso/Downloads/Ph-Builds
# $5 IMG_TYPE        default minimal-iso
# $6 CANISTER_MODE   default none

set -eu

echo "[runPh7-2-7] wrapper v4"

SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)

find_file() {
  name="$1"
  for d in "$SCRIPT_DIR" "$SCRIPT_DIR/staging" "$HOME" "$HOME/staging" \
           /root /root/staging /root/photonos-scripts/staging; do
    [ -f "$d/$name" ] && { echo "$d/$name"; return 0; }
  done
  return 1
}

SRC=$(find_file runPh5_normal.sh) || {
  echo "[runPh7-2-7] ERROR: runPh5_normal.sh not found" 1>&2
  exit 1
}

BASE_DIR="${1:-/root}"
COMMON_BRANCH="${2:-common}"
RELEASE_BRANCH="${3:-experimental/linux-7.2.7}"
OUTPUT_DIR="${4:-/mnt/c/Users/dcaso/Downloads/Ph-Builds}"
IMG_TYPE="${5:-minimal-iso}"
CANISTER_MODE="${6:-none}"

if [ "$CANISTER_MODE" = "prebuilt" ]; then
  echo "[runPh7-2-7] WARNING: prebuilt canister is a 6.12 artifact; forcing mode=none"
  CANISTER_MODE=none
fi

# If a previous run already nested the clone, fix the layout now.
fix_common_layout() {
  rel="$BASE_DIR/$RELEASE_BRANCH"
  com="$BASE_DIR/$COMMON_BRANCH"
  parent=$(dirname "$rel")
  mkdir -p "$parent"
  if [ -d "$com" ] && [ "$parent" != "$BASE_DIR" ]; then
    ln -sfn "$com" "$parent/common"
    echo "[runPh7-2-7] $parent/common -> $com"
  fi
  if [ -f "$rel/build-config.json" ]; then
    python3 -c "
import json
p='$rel/build-config.json'
c=json.load(open(p))
c['common-branch-path']='$com'
json.dump(c, open(p,'w'), indent=4)
print('[runPh7-2-7] common-branch-path =', c['common-branch-path'])
"
  fi
}
fix_common_layout

GEN=$(mktemp /tmp/runPh7-2-7.XXXXXX.sh)
PINOUT=$(mktemp /tmp/pin-linux-7.2.7.XXXXXX.sh)
trap 'rm -f "$GEN" "$PINOUT"' EXIT

cat > "$PINOUT" << EMBEDPIN
# Sourced after downstream-fixes. Expects BASE_DIR, COMMON_BRANCH, RELEASE_BRANCH.
pin_727() {
  spec="\$1"
  patch="\$2"
  [ -f "\$spec" ] || return 1
  if grep -q '^Version:[[:space:]]*7.2.7' "\$spec"; then
    echo "[runPh7-2-7] \$spec already Version 7.2.7"
    return 0
  fi
  if [ -f "\$patch" ] && patch -p1 --forward --dry-run < "\$patch" >/dev/null 2>&1; then
    patch -p1 --forward < "\$patch" && echo "[runPh7-2-7] Applied \$(basename "\$patch")"
    return 0
  fi
  echo "[runPh7-2-7] WARNING: pin patch missed for \$spec; forcing Version/Source0/fips with sed"
  sed -i 's/^Version:[[:space:]]*6\.12\.[0-9]\+/Version:        7.2.7/' "\$spec"
  sed -i 's#pub/linux/kernel/v6.x/linux-#pub/linux/kernel/v7.x/linux-#' "\$spec"
  awk 'BEGIN{done=0} /%global fips 1/ && !done {sub(/%global fips 1/,"%global fips 0"); done=1} {print}' \
    "\$spec" > "\$spec.pin" && mv "\$spec.pin" "\$spec"
}

cd "\$BASE_DIR/\$RELEASE_BRANCH" || exit 1
parent=\$(dirname "\$BASE_DIR/\$RELEASE_BRANCH")
if [ "\$parent" != "\$BASE_DIR" ] && [ -d "\$BASE_DIR/\${COMMON_BRANCH:-common}" ]; then
  ln -sfn "\$BASE_DIR/\${COMMON_BRANCH:-common}" "\$parent/common"
  echo "[runPh7-2-7] \$parent/common -> \$BASE_DIR/\${COMMON_BRANCH:-common}"
fi
if [ -f build-config.json ]; then
  python3 -c "
import json
p='build-config.json'
c=json.load(open(p))
c['common-branch-path']='\$BASE_DIR/\${COMMON_BRANCH:-common}'
json.dump(c, open(p,'w'), indent=4)
print('[runPh7-2-7] common-branch-path =', c['common-branch-path'])
"
fi
pin_727 SPECS/linux/linux.spec SPECS/linux/linux.spec.7.2.7.patch
pin_727 SPECS/linux/linux-esx.spec SPECS/linux/linux-esx.spec.7.2.7.patch
kver=\$(awk '/^Version:/{print \$2; exit}' SPECS/linux/linux.spec 2>/dev/null)
echo "[runPh7-2-7] linux.spec Version=\$kver"
if [ "\$kver" != "7.2.7" ]; then
  echo "[runPh7-2-7] ERROR: linux.spec Version is '\$kver', expected 7.2.7" 1>&2
  exit 1
fi
EMBEDPIN

sed \
  -e 's/\[runPh5_normal\]/[runPh7-2-7]/g' \
  -e 's/\.runph5-iso-marker/.runph727-iso-marker/g' \
  -e 's/RELEASE_BRANCH="${3:-5.0}"/RELEASE_BRANCH="${3:-experimental\/linux-7.2.7}"/' \
  -e 's/CANISTER_MODE="${6:-prebuilt}"/CANISTER_MODE="${6:-none}"/' \
  -e 's/prebuilt|build|acvp|kat)/none|prebuilt|build|acvp|kat)/' \
  -e "s/{'prebuilt': \\[\\]/{'none': [], 'prebuilt': []/g" \
  "$SRC" > "$GEN"

python3 - "$GEN" "$PINOUT" << 'PY'
import sys
from pathlib import Path
gen, pin = Path(sys.argv[1]), sys.argv[2]
lines = gen.read_text().splitlines(keepends=True)
out, i, replaced = [], 0, False
while i < len(lines):
    if (not replaced) and 'if git apply "$DOWNSTREAM_PATCH"' in lines[i]:
        depth, started = 0, False
        while i < len(lines):
            l = lines[i]
            if l.lstrip().startswith('if '):
                depth += 1
                started = True
            if l.lstrip().startswith('fi'):
                depth -= 1
                i += 1
                if started and depth == 0:
                    break
                continue
            i += 1
        out.append('''    if git apply "$DOWNSTREAM_PATCH"; then
      echo "[runPh7-2-7] Applied downstream-fixes.patch"
    elif git apply --exclude='SPECS/linux/*' --exclude='SPECS/90/*' --exclude='SPECS/openssh/*' --exclude='SPECS/stig-hardening/stig-hardening.spec' "$DOWNSTREAM_PATCH"; then
      echo "[runPh7-2-7] Applied downstream-fixes.patch with stale-spec excludes"
    else
      echo "[runPh7-2-7] WARNING: downstream-fixes.patch still does not apply; continuing" 1>&2
    fi
''')
        replaced = True
        continue
    out.append(lines[i])
    i += 1
text = ''.join(out)
idx = text.find('NOTE: photonos-patches/downstream-fixes.patch not found')
if idx < 0:
    sys.exit('NOTE line missing')
fi_at = text.find('\n  fi\n', idx)
if fi_at < 0:
    sys.exit('closing fi missing')
insert_at = fi_at + len('\n  fi\n')
text = text[:insert_at] + f'\n  . "{pin}"\n' + text[insert_at:]

# Re-apply the common-path fix immediately before every make (git checkout
# -- build-config.json later in runPh5_normal.sh would otherwise reset it).
fix = '''
  rel="$BASE_DIR/$RELEASE_BRANCH"
  com="$BASE_DIR/$COMMON_BRANCH"
  parent=$(dirname "$rel")
  if [ -d "$com" ] && [ "$parent" != "$BASE_DIR" ]; then
    ln -sfn "$com" "$parent/common"
  fi
  if [ -f "$rel/build-config.json" ]; then
    python3 -c "import json; p='$rel/build-config.json'; c=json.load(open(p)); c['common-branch-path']='$com'; json.dump(c, open(p,'w'), indent=4)"
  fi
'''
text2 = []
for line in text.splitlines(keepends=True):
    if 'sudo make' in line or (line.lstrip().startswith('make ') and 'image' in line):
        text2.append(fix)
    text2.append(line)
text = ''.join(text2)
if not replaced:
    sys.exit('apply block missing')
gen.write_text(text)
print('[runPh7-2-7] generated apply+pin+common-path rewrite ok')
PY

chmod +x "$GEN" "$PINOUT"
echo "[runPh7-2-7] using $SRC"
echo "[runPh7-2-7] Image type: $IMG_TYPE"
echo "[runPh7-2-7] Canister mode: $CANISTER_MODE"
echo "[runPh7-2-7] Release branch: $RELEASE_BRANCH"
exec /bin/sh "$GEN" "$BASE_DIR" "$COMMON_BRANCH" "$RELEASE_BRANCH" "$OUTPUT_DIR" "$IMG_TYPE" "$CANISTER_MODE"
