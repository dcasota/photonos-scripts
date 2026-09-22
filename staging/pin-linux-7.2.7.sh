# Sourced by runPh7-2-7.sh after downstream-fixes.patch.
# Expects BASE_DIR and RELEASE_BRANCH.
pin_727() {
  spec="$1"
  patch="$2"
  [ -f "$spec" ] || return 1
  if grep -q '^Version:[[:space:]]*7.2.7' "$spec"; then
    echo "[runPh7-2-7] $spec already Version 7.2.7"
    return 0
  fi
  if [ -f "$patch" ] && patch -p1 --forward --dry-run < "$patch" >/dev/null 2>&1; then
    patch -p1 --forward < "$patch" && echo "[runPh7-2-7] Applied $(basename "$patch")"
    return 0
  fi
  echo "[runPh7-2-7] WARNING: pin patch missed for $spec; forcing Version/Source0/fips with sed"
  sed -i 's/^Version:[[:space:]]*6\.12\.[0-9]\+/Version:        7.2.7/' "$spec"
  sed -i 's#pub/linux/kernel/v6.x/linux-#pub/linux/kernel/v7.x/linux-#' "$spec"
  awk 'BEGIN{done=0} /%global fips 1/ && !done {sub(/%global fips 1/,"%global fips 0"); done=1} {print}' \
    "$spec" > "$spec.pin" && mv "$spec.pin" "$spec"
}

cd "$BASE_DIR/$RELEASE_BRANCH" || exit 1
pin_727 SPECS/linux/linux.spec SPECS/linux/linux.spec.7.2.7.patch
pin_727 SPECS/linux/linux-esx.spec SPECS/linux/linux-esx.spec.7.2.7.patch

K727_SHA="9a7ee3e35e1e4eea44fd2fadce7b51deb9cae8b1e19ed4d8dc1e59d2e310ffa6dae508a9b0919d2d3cd29d00ca79fd473e7540a3cfb1124e56c4de091915a9d9"
if command -v fetch_or_validate_source >/dev/null 2>&1; then
  fetch_or_validate_source \
    "linux-7.2.7.tar.xz" \
    "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.7.tar.xz" \
    "$K727_SHA" || true
else
  dest="$BASE_DIR/$RELEASE_BRANCH/stage/SOURCES"
  mkdir -p "$dest"
  if [ ! -f "$dest/linux-7.2.7.tar.xz" ]; then
    echo "[runPh7-2-7] Fetching linux-7.2.7.tar.xz from kernel.org"
    wget -q -O "$dest/linux-7.2.7.tar.xz.tmp" \
      "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.7.tar.xz" && \
      mv "$dest/linux-7.2.7.tar.xz.tmp" "$dest/linux-7.2.7.tar.xz" || \
      rm -f "$dest/linux-7.2.7.tar.xz.tmp"
  fi
fi
kver=$(awk '/^Version:/{print $2; exit}' SPECS/linux/linux.spec 2>/dev/null)
echo "[runPh7-2-7] linux.spec Version=$kver"
if [ "$kver" != "7.2.7" ]; then
  echo "[runPh7-2-7] ERROR: linux.spec Version is '$kver', expected 7.2.7" 1>&2
  exit 1
fi
