# oracle.sh - the pass/fail assertions. Source after common.sh.
#
# Every assertion names the PR it proves. That is the point: a run does not
# report "something broke", it reports "PR #22 regressed", because the whole
# purpose of this harness is to make PR issues identifiable.
#
# The permutation matrix supplies a *dependency-resolution* oracle only
# (Error(1011) vs Error(1032), media RPM presence). It supplies nothing for
# dmesg / journalctl / /var/log. Sections C and D below are new work.

# ---- A. media, before any VM exists -------------------------------------
# Six packages that the matrix records as ABSENT from minimal media. Their
# presence is what POI#11 (the doc's FIX-1b) delivers, and their absence is
# the root cause of matrix rows 3,4,7,8 - and, via selinux-policy, 5,6.
MC_STIG_MEDIA_PKGS="rsyslog openssl-fips-provider selinux-policy libselinux-utils aide"

mc_oracle_media() {
    local iso="$1" iso_type="$2"
    local list; list=$(xorriso -osirrox on -indev "$iso" -find /RPMS -name '*.rpm' 2>/dev/null | sed 's|.*/||' | tr -d "'")
    local n; n=$(printf '%s\n' "$list" | grep -c '\.rpm$') || n=0
    mc_check media.rpm_count "-" info "" "$n" "RPMs on media"

    # Negative control: a name that must never resolve. Without it a broken
    # extraction would make every presence check vacuously pass.
    local ctl; ctl=$(printf '%s\n' "$list" | grep -cE '^zzz-not-a-real-package-[0-9]') || ctl=0
    mc_expect media.negative_control "-" "0" "$ctl" "control must find nothing"

    local missing="" p c
    for p in $MC_STIG_MEDIA_PKGS; do
        c=$(printf '%s\n' "$list" | grep -cE "^${p}-[0-9]") || c=0
        [ "$c" -eq 0 ] && missing="$missing $p"
    done
    # ntp is a capability satisfied by ntpsec; no package is literally named ntp.
    c=$(printf '%s\n' "$list" | grep -cE '^ntpsec-[0-9]') || c=0
    [ "$c" -eq 0 ] && missing="$missing ntpsec"
    mc_expect media.stig_packages "POI#11" "" "${missing# }" "STIG set must be on the media for minimal-iso"

    # Stale-RPM shadowing: tdnf picks the highest release, so a months-old
    # photon-os-installer left in stage/RPMS silently wins and ends up on the
    # ISO. Record what actually shipped.
    local poi; poi=$(printf '%s\n' "$list" | grep -oE '^photon-os-installer-[0-9][^ ]*\.rpm' | head -1)
    mc_check media.poi_rpm "-" info "" "${poi:-ABSENT}" "installer actually on the media"
}

# ---- B. install phase, from the serial log ------------------------------
mc_oracle_install() {
    local serial="$1"
    [ -f "$serial" ] || { mc_check install.serial_log "-" fail "present" "missing" "$serial"; return 1; }

    # Error(1011) is a genuine resolution failure. Error(1032) is only ever a
    # --assumeno dry-run artifact and must NOT be treated as a real-install
    # signal. Never match a specific package name: list(set(packages)) makes
    # which of the six tdnf reports first non-deterministic.
    local e1011; e1011=$(mc_grep_count 'Error(1011)' "$serial")
    mc_expect install.no_error_1011 "POI#11" "0" "$e1011" "No matching packages"

    local efail; efail=$(mc_grep_count 'Failed to install some packages' "$serial")
    mc_expect install.packages_installed "POI#11" "0" "$efail" ""

    # The i18n error proves the locale.conf ordering fix did NOT apply.
    local i18n; i18n=$(mc_grep_count 'i18n_vars not set' "$serial")
    mc_expect install.no_i18n_error "POI#10" "0" "$i18n" "dracut 20i18n needs /etc/locale.conf at initrd build time"

    # The single most valuable completion signal: the boot source moves from
    # the installer live env to the installed disk.
    local ram parts
    ram=$(mc_grep_count 'root=/dev/ram0' "$serial")
    parts=$(mc_grep_count 'root=PARTUUID=' "$serial")
    mc_check install.boot_ram0 "-" info "" "$ram" "installer live-env boots"
    mc_expect install.booted_from_disk "-" "yes" "$([ "$parts" -gt 0 ] && echo yes || echo no)" \
        "root=PARTUUID= means the install completed and the VM rebooted off disk"

    local ansfail; ansfail=$(mc_grep_count 'AssertionError' "$serial")
    mc_expect install.ansible_no_assert "PR#9" "0" "$ansfail" "installer.py asserts on playbook returncode"
}

# ---- C. post-boot, over ssh ---------------------------------------------
# $1 is a function name that runs a command in the guest and prints stdout.
mc_oracle_guest() {
    local run="$1" stig="$2" fs="$3" canister="${4:-prebuilt}"
    local v

    v=$($run 'findmnt -no FSTYPE /' 2>/dev/null | tr -d ' ')
    mc_expect guest.root_fstype "-" "$fs" "${v:-unknown}" "the filesystem axis actually took effect"

    v=$($run 'getenforce' 2>/dev/null | tr -d ' ')
    if [ "$stig" = yes ]; then
        mc_expect guest.selinux "PR#9" "Enforcing" "${v:-unknown}" ""
    else
        mc_check guest.selinux "PR#9" info "" "${v:-unknown}" ""
    fi

    # PR#22: both group regressions are visible in the journal of every boot.
    v=$($run "journalctl -b --no-pager 2>/dev/null | grep -c \"Unknown group 'render'\"" 2>/dev/null | tr -d ' ')
    mc_expect guest.no_render_group "PR#22" "0" "${v:-?}" "dangling accel rule in 50-udev-default.rules"
    v=$($run "journalctl -b --no-pager 2>/dev/null | grep -c \"resolve group 'systemd-journal'\"" 2>/dev/null | tr -d ' ')
    mc_expect guest.no_journal_group "PR#22" "0" "${v:-?}" "initrd sysusers snippet emptied by systemd patch 0004"

    # PR#22 again: /tmp hardening is delivered at build time because
    # tmp.mount is package-owned and not %config; the installer deliberately
    # skips the equivalent ansible control PHTN-50-000245.
    if [ "$stig" = yes ]; then
        v=$($run 'findmnt -no OPTIONS /tmp' 2>/dev/null | grep -c noexec) || v=0
        mc_check guest.tmp_noexec "PR#22" info "" "$v" "1 once STIG_HARDEN builds are enabled"
    fi

    # POI#9: exactly five STIG packages requested, not eight.
    v=$($run "zcat /var/log/poi/manifest.json.gz 2>/dev/null | python3 -c \"import json,sys;print(len(json.load(sys.stdin)['install_config'].get('additional_packages',[])))\"" 2>/dev/null | tr -d ' ')
    if [ "$stig" = yes ]; then
        mc_expect guest.stig_pkg_count "POI#9" "5" "${v:-?}" "libselinux-utils, ntp, libgcrypt dropped as redundant"
    fi

    # The matrix's own cheap assertion: stig-hardening runs from the initrd
    # and must never land on the target.
    v=$($run 'rpm -q stig-hardening >/dev/null 2>&1 && echo installed || echo absent' 2>/dev/null | tr -d ' ')
    mc_expect guest.stig_not_on_target "-" "absent" "${v:-?}" "stig-hardening is not in KS_STIG_PACKAGES"

    # PR#21: versioned libgcrypt only at subrelease >= 91.
    v=$($run 'rpm -q --requires aide 2>/dev/null | grep -c "libgcrypt >= 1.10.4"' 2>/dev/null | tr -d ' ')
    mc_check guest.aide_libgcrypt "PR#21" info "" "${v:-0}" "1 only when built at subrelease >= 91"

    # POI#9 counterpart: time sync works without ntp being installed.
    v=$($run 'timedatectl show -p NTPSynchronized --value' 2>/dev/null | tr -d ' ')
    mc_check guest.time_synced "POI#9" info "" "${v:-?}" "systemd-timesyncd, not ntp"

    # Canister/FIPS, when the ISO was built with one.
    v=$($run 'cat /proc/sys/crypto/fips_enabled 2>/dev/null' 2>/dev/null | tr -d ' ')
    mc_check guest.fips_enabled "PR#24" info "" "${v:-0}" ""
    v=$($run 'dmesg 2>/dev/null | grep -c "canister verification passed"' 2>/dev/null | tr -d ' ')
    mc_check guest.fips_canister "PR#24" info "" "${v:-0}" ""

    v=$($run 'systemctl --failed --no-legend --no-pager 2>/dev/null | wc -l' 2>/dev/null | tr -d ' ')
    mc_expect guest.failed_units "PR#9" "0" "${v:-?}" "first boot may race the SELinux relabel; second boot must be clean"

    v=$($run 'journalctl -b --no-pager 2>/dev/null | grep -ci "avc: *denied"' 2>/dev/null | tr -d ' ')
    mc_check guest.avc_denials "PR#9" info "" "${v:-?}" "non-zero on first boot is the documented relabel race"
}

# ---- D. log harvest ------------------------------------------------------
# The matrix defines no dmesg/journalctl//var/log criteria at all, so this
# collects the evidence rather than asserting on it - except for the two
# counts, which are cheap regression detectors.
mc_oracle_harvest() {
    local run="$1" dest="$2"
    mkdir -p "$dest"
    $run 'dmesg'                                   > "$dest/dmesg.txt"            2>/dev/null
    $run 'journalctl -b --no-pager'                > "$dest/journal-boot.txt"     2>/dev/null
    $run 'journalctl -p err -b --no-pager'         > "$dest/journal-err.txt"      2>/dev/null
    $run 'systemctl --failed --no-pager'           > "$dest/failed-units.txt"     2>/dev/null
    $run 'rpm -qa | sort'                          > "$dest/rpm-qa.txt"           2>/dev/null
    $run 'cat /proc/cmdline'                       > "$dest/cmdline.txt"          2>/dev/null
    $run 'findmnt -A'                              > "$dest/mounts.txt"           2>/dev/null
    for f in installer.log ansible-stig.log messages; do
        $run "cat /var/log/$f 2>/dev/null" > "$dest/varlog-$f" 2>/dev/null
    done
    $run 'cat /var/log/mkinitrd-*.log 2>/dev/null' > "$dest/varlog-mkinitrd.txt"  2>/dev/null
    $run 'zcat /var/log/poi/manifest.json.gz 2>/dev/null' > "$dest/poi-manifest.json" 2>/dev/null

    local d j
    d=$(grep -cE '\] (BUG|WARNING|Oops|Call Trace)' "$dest/dmesg.txt" 2>/dev/null) || d=0
    mc_expect logs.dmesg_no_bug "-" "0" "$d" "kernel BUG/WARNING/Oops in dmesg"
    j=$(wc -l < "$dest/journal-err.txt" 2>/dev/null) || j=0
    mc_check logs.journal_err_lines "-" info "" "$j" "harvested to journal-err.txt"
}
