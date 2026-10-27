# 90-teardown - return the VM to a fresh-disk state.
#
# ASCII-ONLY BY POLICY - see the note at the top of 10-create-vm.ps1. Windows
# PowerShell 5.1 reads .ps1 as ANSI without a BOM, so one non-ASCII character
# corrupts a string literal and produces a cascade of misleading parse errors.
#
# NOTHING IS DELETED. Every displaced file is renamed with a
# `.stashed-<timestamp>` suffix; recovery is a rename back. That is both the
# project rule (no destructive action without an explicit per-instance go)
# and good practice - the previous boot disk is the only post-mortem material
# for whatever went wrong on it.
#
# PRESERVED, always:
#   * operator-config.vmdk / operator-config-flat.vmdk - the credential
#     medium on scsi0:1. install-from-iso never touches scsi0:1, so it is
#     meant to outlive any number of reinstalls. Regenerating it is a
#     separate, deliberate act.
#   * every serial0-*.log - the only diagnostic record of past boots.
#   * the .vmx - it holds the pinned MAC/UUID that keep the guest's IP.
#
# WHY THE WHOLE CHAIN GOES, NOT JUST THE DISK: if any of the snapshot delta,
# .vmsd, .vmsn or NVRAM survives, UEFI's removable-media fallback finds the
# old ESP's \EFI\BOOT\BOOTX64.EFI and boots the PREVIOUS image. bios.bootOrder
# is ignored on EFI VMs, and deleting NVRAM alone does not help because UEFI
# re-detects the disk.
[CmdletBinding()]
param(
    # Also stash the VMX (forces 10-create-vm.ps1 to regenerate it from the
    # template). Off by default - the VMX holds the pinned MAC/UUID.
    [switch]$IncludeVmx,
    # Required. Teardown is destructive-shaped even though it only renames.
    [switch]$Confirm
)
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
# Same parser as 10-create-vm.ps1 - see the trailing-comment note there.
$cfg = @{}
foreach ($line in Get-Content (Join-Path $here '..\config\vm-lab.env')) {
    if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
    # vm-lab.env uses the override-safe form  : "${KEY:=VALUE}"  so that an
    # exported value wins. Accept the older KEY=VALUE form too, so a stale
    # copy of the file still parses.
    if ($line -match '^\s*:\s*"\$\{([A-Za-z_][A-Za-z0-9_]*):=(.*)\}"\s*$') {
        $k = $Matches[1]
        $v = $Matches[2]
    }
    elseif ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)=\s*(.*)$') {
        $k = $Matches[1]
        $raw = $Matches[2]
        if ($raw -match '^"([^"]*)"') { $v = $Matches[1] }
        elseif ($raw -match "^'([^']*)'") { $v = $Matches[1] }
        else { $v = (($raw -split '#', 2)[0]).Trim() }
    }
    else { continue }
    # An environment value overrides the file, matching what the .sh scripts
    # now do. Without this the README's documented per-run overrides work in
    # bash but are silently ignored on the PowerShell side.
    $envVal = [Environment]::GetEnvironmentVariable($k)
    if ($envVal) { $cfg[$k] = $envVal; continue }
    $v = [regex]::Replace($v, '\$\{([A-Za-z_][A-Za-z0-9_]*)\}', { param($m) if ($cfg.ContainsKey($m.Groups[1].Value)) { $cfg[$m.Groups[1].Value] } else { '' } })
    $v = $v -replace '\\\\', '\'
    $cfg[$k] = $v
}
$vmName = $cfg['VM_NAME']
$vmDir  = $cfg['VM_DIR_WIN']
$vmrun  = Join-Path $cfg['VMWARE_DIR_WIN'] 'vmrun.exe'
$med    = $cfg['OPERATOR_MEDIUM_BASENAME']

if (-not $Confirm) {
    Write-Output "This will stash the boot disk + firmware state of '$vmName' in:"
    Write-Output "  $vmDir"
    Write-Output ""
    Write-Output "Nothing is deleted - files are renamed .stashed-<ts>."
    Write-Output "The operator medium and all serial logs are preserved."
    Write-Output ""
    Write-Output "Re-run with -Confirm to proceed."
    exit 0
}

Write-Output "=== refuse if the VM is running ==="
if (Test-Path $vmrun) {
    $running = & $vmrun -T ws list
    if ($running -match [regex]::Escape($vmName)) {
        throw "$vmName is RUNNING. Stop it first. Refusing to touch its disk."
    }
    Write-Output "  not running"
}

$ts = Get-Date -Format 'yyyyMMddTHHmmssZ'
# Enumerated by pattern, not by name. The previous fixed list covered exactly
# two snapshot deltas and two .vmsn files, so a VM that had reached
# -000003.vmdk left an orphan behind - which defeats the whole point stated
# at the top of this file, because UEFI's removable-media fallback then finds
# the surviving ESP and boots the PREVIOUS image.
$targets = @("$vmName.vmdk", "$vmName.vmsd", "nvram", "$vmName.vmx.lck")
$targets += (Get-ChildItem -LiteralPath $vmDir -Filter "$vmName-*.vmdk" -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -match "^$([regex]::Escape($vmName))-\d{6}\.vmdk$" } |
             ForEach-Object { $_.Name })
$targets += (Get-ChildItem -LiteralPath $vmDir -Filter '*.vmsn' -ErrorAction SilentlyContinue |
             ForEach-Object { $_.Name })
$targets = $targets | Select-Object -Unique
if ($IncludeVmx) { $targets += "$vmName.vmx" }

Write-Output ""
Write-Output "=== stashing (NOT deleting) ==="
$moved = 0
foreach ($n in $targets) {
    $p = Join-Path $vmDir $n
    if (Test-Path $p) {
        Move-Item -LiteralPath $p -Destination "$p.stashed-$ts" -Force
        Write-Output ("  moved  {0,-32} -> {0}.stashed-{1}" -f $n, $ts)
        $moved++
    }
}
if ($moved -eq 0) { Write-Output "  nothing to stash (already clean)" }

Write-Output ""
Write-Output "=== the credential medium must have survived ==="
foreach ($n in @("$med.vmdk", "$med-flat.vmdk")) {
    $p = Join-Path $vmDir $n
    if (Test-Path $p) {
        "  OK      {0,-30} {1,14:n0} bytes" -f $n, (Get-Item $p).Length
    } else {
        Write-Output "  ABSENT  $n  (the next install will boot KEYLESS)"
    }
}
$flatPath = Join-Path $vmDir "$med-flat.vmdk"
if (Test-Path $flatPath) {
    $want = [int64]$cfg['OPERATOR_MEDIUM_FLAT_BYTES']
    $got  = (Get-Item $flatPath).Length
    if ($got -ne $want) {
        Write-Output "  *** flat size $got != expected $want - this is not the verified medium ***"
    } else {
        Write-Output "  flat size matches the verified medium"
    }
}

Write-Output ""
Write-Output "=== serial logs preserved ==="
Get-ChildItem $vmDir -Filter "$($cfg['SERIAL_LOG_PREFIX'])-*.log" -ErrorAction SilentlyContinue |
    ForEach-Object { "  {0,-46} {1,14:n0}" -f $_.Name, $_.Length }

Write-Output ""
Write-Output "=== stashed this run (recover by renaming back) ==="
Get-ChildItem $vmDir -Filter "*.stashed-$ts" -ErrorAction SilentlyContinue |
    ForEach-Object { "  {0,-58} {1,14:n0}" -f $_.Name, $_.Length }

Write-Output ""
Write-Output "NEXT: scripts/10-create-vm.ps1 (recreates the boot disk; add -RefreshVmxOnly if you stashed the VMX)"
