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
    # nrfjprog --memwr exits non-zero with "perform no operation" when the
    # target already holds the requested value (re-provisioning the same id/
    # label). That's harmless for us. Drop the error preference locally so
    # PowerShell 5.1 doesn't turn nrfjprog's stderr (via 2>&1) into a
    # terminating NativeCommandError before we can inspect the message.
    $ErrorActionPreference = 'Continue'
    $output = (& nrfjprog -f nrf52 @snrArg @Arguments 2>&1 | Out-String)
    Write-Host $output.TrimEnd()
    if ($LASTEXITCODE -ne 0) {
        if ($output -match 'perform no operation') {
            Write-Host "  note: value already programmed; continuing." -ForegroundColor Yellow
        } else {
            throw "nrfjprog failed: nrfjprog $($Arguments -join ' ')"
        }
    }
}

if ($EraseUicr) {
    Write-Host "Erasing UICR page..."
    Invoke-Nrfjprog @("--eraseuicr")
}

Write-Host "Writing anchor id $AnchorId to UICR.CUSTOMER[0]..."
Invoke-Nrfjprog @("--memwr", "0x10001080", "--val", "0x{0:X8}" -f $AnchorId)

# UICR bits only flip 1->0, so writing a new id over an already-programmed
# board silently does nothing (nrfjprog reports "no operation"). Read it back
# and fail clearly before touching the label, instead of limping on.
$ErrorActionPreference = 'Continue'
$readback = (& nrfjprog -f nrf52 @snrArg --memrd 0x10001080 --n 4 2>&1 | Out-String)
if ($readback -match '0x10001080:\s*([0-9A-Fa-f]{8})') {
    $got = [Convert]::ToUInt32($Matches[1], 16)
    if ($got -ne $AnchorId) {
        throw ("Anchor id readback is 0x{0:X8}, expected 0x{1:X8}. This board's UICR is already programmed (flash bits only clear, never set). Re-run with -EraseUicr to change it." -f $got, $AnchorId)
    }
    Write-Host ("  verified id = 0x{0:X8}" -f $got) -ForegroundColor Green
}

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
