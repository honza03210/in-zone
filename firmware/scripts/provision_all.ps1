<#
.SYNOPSIS
  Provision all 4 DWM3001CDK anchors in sequence. Prompts you to connect
  each board one at a time via USB, then writes anchor ID + label to UICR.

  Default labels are positional ("door", "window", "desk", "bed") but you
  can override them with -Labels.

.EXAMPLE
  .\provision_all.ps1
  .\provision_all.ps1 -Labels "north","south","east","west"
  .\provision_all.ps1 -EraseUicr   # re-provision all boards from scratch
#>
param(
    [string[]]$Labels = @("door", "window", "desk", "bed"),
    [switch]$EraseUicr
)

$ErrorActionPreference = "Stop"

if ($Labels.Count -ne 4) {
    throw "Exactly 4 labels required, got $($Labels.Count)"
}

Write-Host ""
Write-Host "=== In-Zone Anchor Provisioning ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will provision 4 anchors with IDs 0-3."
Write-Host "Connect one board at a time when prompted."
Write-Host ""

for ($id = 0; $id -lt 4; $id++) {
    $label = $Labels[$id]
    Write-Host "--- Anchor $id ('$label') ---" -ForegroundColor Yellow
    Write-Host "Connect anchor board $id via USB and press Enter..."
    Read-Host | Out-Null

    # Verify a single J-Link is connected
    $probes = & nrfjprog --ids 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $probes) {
        Write-Host "ERROR: No J-Link found. Is the board connected?" -ForegroundColor Red
        Write-Host "Press Enter to retry, or Ctrl+C to abort."
        Read-Host | Out-Null
        $id--
        continue
    }

    $probeList = $probes -split "`n" | Where-Object { $_ -match '\d+' }
    if ($probeList.Count -gt 1) {
        Write-Host "WARNING: Multiple J-Links detected. Disconnect all but anchor $id." -ForegroundColor Red
        Write-Host "Press Enter to retry, or Ctrl+C to abort."
        Read-Host | Out-Null
        $id--
        continue
    }

    $eraseArg = if ($EraseUicr) { @("-EraseUicr") } else { @() }
    & "$PSScriptRoot\provision.ps1" -AnchorId $id -Label $label @eraseArg

    Write-Host ""
    Write-Host "Verifying..." -ForegroundColor Gray
    & "$PSScriptRoot\read_uicr.ps1"
    Write-Host ""
}

Write-Host "=== All 4 anchors provisioned ===" -ForegroundColor Green
Write-Host ""
Write-Host "Summary:"
for ($id = 0; $id -lt 4; $id++) {
    Write-Host ("  Anchor {0}: InZone-A{0}  label='{1}'" -f $id, $Labels[$id])
}
Write-Host ""
