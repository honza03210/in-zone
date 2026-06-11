<#
.SYNOPSIS
  Read and display the provisioned anchor identity from a DWM3001CDK's UICR.
  Useful for verifying what's on a board before or after provisioning.

.EXAMPLE
  .\read_uicr.ps1
  .\read_uicr.ps1 -Snr 760012345   # specific J-Link serial
#>
param(
    [string]$Snr = ""
)

$ErrorActionPreference = "Stop"
$snrArg = if ($Snr) { @("--snr", $Snr) } else { @() }

function Read-Word {
    param([string]$Address)
    $output = & nrfjprog -f nrf52 @snrArg --memrd $Address --n 4
    if ($LASTEXITCODE -ne 0) { throw "nrfjprog --memrd failed at $Address" }
    # Output format: "0x10001080: FFFFFFFF"
    if ($output -match ':\s*([0-9A-Fa-f]{8})') {
        return [Convert]::ToUInt32($Matches[1], 16)
    }
    throw "Unexpected nrfjprog output: $output"
}

# Read anchor ID from CUSTOMER[0] @ 0x10001080
$idRaw = Read-Word "0x10001080"

if ($idRaw -gt 3) {
    $idStr = "UNPROVISIONED (0x{0:X8})" -f $idRaw
} else {
    $idStr = "$idRaw"
}

# Read label from CUSTOMER[4..7] @ 0x10001090 (16 bytes = 4 words)
$labelBytes = New-Object byte[] 16
for ($w = 0; $w -lt 4; $w++) {
    $addr = "0x{0:X8}" -f (0x10001090 + $w * 4)
    $val = Read-Word $addr
    $wordBytes = [BitConverter]::GetBytes($val)
    [Array]::Copy($wordBytes, 0, $labelBytes, $w * 4, 4)
}

# Trim 0xFF and NUL padding
$labelLen = 0
for ($i = 0; $i -lt 16; $i++) {
    if ($labelBytes[$i] -eq 0xFF -or $labelBytes[$i] -eq 0x00) { break }
    $labelLen++
}

if ($labelLen -gt 0) {
    $label = [System.Text.Encoding]::UTF8.GetString($labelBytes, 0, $labelLen)
} else {
    $label = "(empty)"
}

Write-Host ""
Write-Host "  Anchor ID : $idStr"
Write-Host "  Label     : $label"
if ($idRaw -le 3) {
    Write-Host "  Adv Name  : InZone-A$idRaw"
} else {
    Write-Host "  Adv Name  : InZone-Ax"
}
Write-Host ""
