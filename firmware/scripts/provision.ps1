<#
.SYNOPSIS
  Provision a DWM3001CDK anchor: write anchor ID (0-3) and optional label
  into nRF52833 UICR customer registers via the on-board J-Link.

  UICR.CUSTOMER[0]  @ 0x10001080  anchor id
  UICR.CUSTOMER[4+] @ 0x10001090  label, up to 16 UTF-8 bytes, 0xFF padded

  UICR bits can only be written 1 -> 0, so re-provisioning a different
  value requires erasing the UICR page (-EraseUicr), which also clears
  it completely. Application flash is not touched. Run with one board
  connected, or pass -Snr to pick one of several.

.EXAMPLE
  .\provision.ps1 -AnchorId 2 -Label "window"
  .\provision.ps1 -AnchorId 0 -EraseUicr   # re-provision a used board
#>
param(
    [Parameter(Mandatory = $true)][ValidateRange(0, 3)][int]$AnchorId,
    [ValidateLength(0, 16)][string]$Label = "",
    [string]$Snr = "",
    [switch]$EraseUicr
)

$ErrorActionPreference = "Stop"
$snrArg = if ($Snr) { @("--snr", $Snr) } else { @() }

function Invoke-Nrfjprog {
    param([string[]]$Arguments)
    & nrfjprog -f nrf52 @snrArg @Arguments
    if ($LASTEXITCODE -ne 0) { throw "nrfjprog failed: nrfjprog $($Arguments -join ' ')" }
}

if ($EraseUicr) {
    Write-Host "Erasing UICR page..."
    Invoke-Nrfjprog @("--eraseuicr")
}

Write-Host "Writing anchor id $AnchorId to UICR.CUSTOMER[0]..."
Invoke-Nrfjprog @("--memwr", "0x10001080", "--val", "0x{0:X8}" -f $AnchorId)

if ($Label) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Label)
    if ($bytes.Length -gt 16) { throw "Label exceeds 16 UTF-8 bytes" }
    # pad to a multiple of 4 with 0xFF and write as little-endian words
    $padded = New-Object byte[] (4 * [math]::Ceiling($bytes.Length / 4))
    for ($i = 0; $i -lt $padded.Length; $i++) {
        $padded[$i] = if ($i -lt $bytes.Length) { $bytes[$i] } else { 0xFF }
    }
    for ($w = 0; $w -lt ($padded.Length / 4); $w++) {
        $val = [BitConverter]::ToUInt32($padded, $w * 4)
        $addr = 0x10001090 + ($w * 4)
        Write-Host ("Writing label word {0} to 0x{1:X8}..." -f $w, $addr)
        Invoke-Nrfjprog @("--memwr", ("0x{0:X8}" -f $addr), "--val", ("0x{0:X8}" -f $val))
    }
}

Write-Host "Resetting..."
Invoke-Nrfjprog @("--reset")
Write-Host "Done. Anchor $AnchorId$(if ($Label) { " ('$Label')" }) provisioned." -ForegroundColor Green
