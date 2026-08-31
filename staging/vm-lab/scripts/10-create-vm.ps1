# 10-create-vm - create the VM directory, the boot VMDK, and the VMX.
#
# ASCII-ONLY BY POLICY. Windows PowerShell 5.1 (`powershell -File ...`) reads
# .ps1 as ANSI unless the file carries a UTF-8 BOM, so a stray em-dash or
# arrow silently corrupts a string literal and the parser then reports a
# cascade of bogus "missing closing brace" errors far from the real line.
# pwsh 7 decodes the same file as UTF-8 and parses it fine, so a parse check
# run under 7 does NOT prove the file runs under 5.1. Keep this file 7-bit.
#
# WHY POWERSHELL: vmware-vdiskmanager.exe and the VMX both want Windows paths,
# and this is the one step that must run on the Windows side.
#
# WHY A TEMPLATE AND NOT THE VMware "New VM" WIZARD: `spagat-vm-orchestrator
# install-from-iso` only EDITS an existing .vmx - it has no createvm /
# vdiskmanager path. So VM creation sits outside the automated loop, which is
# exactly the kind of step that silently drifts. Half the BUG-N series came
# from a VMX key being wrong. The template pins every one of them.
#
# IDEMPOTENCE / SAFETY: this script REFUSES to overwrite an existing boot disk
# or VMX. Re-provisioning is 90-teardown.ps1 (which moves aside, never deletes)
# followed by this script.
[CmdletBinding()]
param(
    # Recreate the VMX from the template even if one exists. Never touches the
    # boot disk or the operator medium.
    [switch]$RefreshVmxOnly
)
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfgPath = Join-Path $here '..\config\vm-lab.env'

# Parse the shell env file: KEY="value" / KEY='value' / KEY=value, ignoring
# comments and blanks. Expands ${VAR} against values already parsed.
#
# TRAILING COMMENTS MATTER. `KEY="value"   # why` must yield `value`, not
# `"value"   # why`. bash strips that for free, so a WSL-side test of the same
# file passes while this parser silently produced a value with a comment glued
# on - which would have been handed straight to vmware-vdiskmanager as an
# adapter name. Match the quoted form first, and for bare values cut at the
# first `#`.
$cfg = @{}
foreach ($line in Get-Content $cfgPath) {
    if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
    if ($line -notmatch '^\s*([A-Za-z_][A-Za-z0-9_]*)=\s*(.*)$') { continue }
    $k = $Matches[1]
    $raw = $Matches[2]
    if ($raw -match '^"([^"]*)"') { $v = $Matches[1] }
    elseif ($raw -match "^'([^']*)'") { $v = $Matches[1] }
    else { $v = (($raw -split '#', 2)[0]).Trim() }
    $v = [regex]::Replace($v, '\$\{([A-Za-z_][A-Za-z0-9_]*)\}', { param($m) if ($cfg.ContainsKey($m.Groups[1].Value)) { $cfg[$m.Groups[1].Value] } else { '' } })
    $v = $v -replace '\\\\', '\'
    $cfg[$k] = $v
}

$vmName   = $cfg['VM_NAME']
$vmDir    = $cfg['VM_DIR_WIN']
$vdm      = Join-Path $cfg['VMWARE_DIR_WIN'] 'vmware-vdiskmanager.exe'
$vmrun    = Join-Path $cfg['VMWARE_DIR_WIN'] 'vmrun.exe'
$vmxPath  = Join-Path $vmDir "$vmName.vmx"
$vmdkPath = Join-Path $vmDir "$vmName.vmdk"
$template = Join-Path $here '..\config\spagat-smoke.vmx.template'

Write-Output "=== target ==="
Write-Output "  VM      : $vmName"
Write-Output "  dir     : $vmDir"
Write-Output "  disk    : $($cfg['BOOT_DISK_SIZE']) $($cfg['BOOT_DISK_ADAPTER']) type=$($cfg['BOOT_DISK_TYPE'])"
Write-Output "  template: $template"

if (-not (Test-Path $vdm)) { throw "vmware-vdiskmanager not found: $vdm" }

Write-Output ""
Write-Output "=== refuse if the VM is running ==="
if (Test-Path $vmrun) {
    $running = & $vmrun -T ws list
    if ($running -match [regex]::Escape($vmName)) {
        throw "$vmName is RUNNING. Stop it first (vmrun stop). Refusing to touch its files."
    }
    Write-Output "  not running"
    Write-Output "  other VMs (left alone):"
    $running | Where-Object { $_ -match '\.vmx$' } | ForEach-Object { "    $_" }
}

if (-not (Test-Path $vmDir)) {
    New-Item -ItemType Directory -Path $vmDir -Force | Out-Null
    Write-Output "  created $vmDir"
}

# --------------------------------------------------------------- boot disk --
Write-Output ""
Write-Output "=== boot disk ==="
if ($RefreshVmxOnly) {
    Write-Output "  -RefreshVmxOnly: leaving the disk alone"
} elseif (Test-Path $vmdkPath) {
    Write-Output "  ALREADY EXISTS - refusing to overwrite: $vmdkPath"
    Write-Output "  To re-provision: run 90-teardown.ps1 first (moves aside, never deletes)."
} else {
    & $vdm -c -s $cfg['BOOT_DISK_SIZE'] -a $cfg['BOOT_DISK_ADAPTER'] -t $cfg['BOOT_DISK_TYPE'] $vmdkPath 2>&1 |
        ForEach-Object { "  $_" }
    if (-not (Test-Path $vmdkPath)) { throw "vdiskmanager did not create $vmdkPath" }
    Write-Output "  created, descriptor says:"
    Get-Content $vmdkPath | Select-String -Pattern '^RW |createType|ddb.adapterType' | ForEach-Object { "    $_" }
}

# --------------------------------------------------------------------- VMX --
Write-Output ""
Write-Output "=== VMX ==="
if ((Test-Path $vmxPath) -and -not $RefreshVmxOnly) {
    Write-Output "  ALREADY EXISTS - refusing to overwrite: $vmxPath"
    Write-Output "  Use -RefreshVmxOnly to regenerate it from the template."
} else {
    if (Test-Path $vmxPath) {
        $bak = "$vmxPath.pre-refresh-$(Get-Date -Format 'yyyyMMddTHHmmssZ')"
        Move-Item -LiteralPath $vmxPath -Destination $bak
        Write-Output "  existing VMX moved aside -> $(Split-Path $bak -Leaf)"
    }
    $serialWin = Join-Path $vmDir "$($cfg['SERIAL_LOG_PREFIX'])-$vmName.log"
    $body = Get-Content $template -Raw
    $body = $body.
        Replace('@@VM_NAME@@',                  $vmName).
        Replace('@@GUEST_VCPUS@@',              $cfg['GUEST_VCPUS']).
        Replace('@@GUEST_MEM_MB@@',             $cfg['GUEST_MEM_MB']).
        Replace('@@GUEST_MAC@@',                $cfg['GUEST_MAC']).
        Replace('@@OPERATOR_MEDIUM_BASENAME@@', $cfg['OPERATOR_MEDIUM_BASENAME']).
        Replace('@@SERIAL_LOG_WIN@@',           $serialWin)
    # VMX files are CRLF + UTF-8 without BOM.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($vmxPath, ($body -replace "`r?`n", "`r`n"), $utf8NoBom)
    Write-Output "  wrote $vmxPath"

    $left = Select-String -Path $vmxPath -Pattern '@@[A-Z_]+@@'
    if ($left) { throw "unsubstituted placeholders remain: $($left -join ', ')" }
    Write-Output "  no placeholders left"
}

# ------------------------------------------------------------------ verify --
Write-Output ""
Write-Output "=== the keys that must be right (drift here is how BUG-Ns start) ==="
$mustHave = 'firmware|secureBoot|bootOrder|sata0.present|scsi0.virtualDev|' +
            'scsi0:0.fileName|scsi0:1.fileName|ethernet0.virtualDev|' +
            'generatedAddress|uuid.bios|serial0.fileName|msg.autoAnswer|' +
            'tools.syncTime|memSize|numvcpus'
Get-Content $vmxPath | Select-String -Pattern $mustHave | ForEach-Object { "  $_" }

Write-Output ""
Write-Output "=== operator medium (NOT created here, see README) ==="
$medNames = @("$($cfg['OPERATOR_MEDIUM_BASENAME']).vmdk", "$($cfg['OPERATOR_MEDIUM_BASENAME'])-flat.vmdk")
foreach ($n in $medNames) {
    $p = Join-Path $vmDir $n
    if (Test-Path $p) {
        "  present {0,-30} {1,14:n0} bytes" -f $n, (Get-Item $p).Length
    } else {
        "  ABSENT  {0,-30} -> the appliance will boot KEYLESS" -f $n
    }
}

Write-Output ""
Write-Output "NEXT: scripts/20-make-ssh-key.sh   (decide SSH access BEFORE building the ISO)"
