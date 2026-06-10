<#
.SYNOPSIS
  Flash a DWM3001CDK anchor: SoftDevice S113 (optional) + application hex.

.EXAMPLE
  .\flash.ps1 -Hex ..\ios-anchor\_build\nrf52833_xxaa.hex `
              -SoftDevice C:\nRF5_SDK_17.1.0\components\softdevice\s113\hex\s113_nrf52_7.2.0_softdevice.hex
  .\flash.ps1 -Hex app.hex            # app only (SoftDevice already present)
#>
param(
    [Parameter(Mandatory = $true)][string]$Hex,
    [string]$SoftDevice = "",
    [string]$Snr = ""
)

$ErrorActionPreference = "Stop"
$snrArg = if ($Snr) { @("--snr", $Snr) } else { @() }

function Invoke-Nrfjprog {
    param([string[]]$Arguments)
    & nrfjprog -f nrf52 @snrArg @Arguments
    if ($LASTEXITCODE -ne 0) { throw "nrfjprog failed: nrfjprog $($Arguments -join ' ')" }
}

if (-not (Test-Path $Hex)) { throw "Application hex not found: $Hex" }

if ($SoftDevice) {
    if (-not (Test-Path $SoftDevice)) { throw "SoftDevice hex not found: $SoftDevice" }
    Write-Host "Programming SoftDevice..."
    Invoke-Nrfjprog @("--program", $SoftDevice, "--sectorerase", "--verify")
}

Write-Host "Programming application..."
Invoke-Nrfjprog @("--program", $Hex, "--sectorerase", "--verify")
Invoke-Nrfjprog @("--reset")
Write-Host "Done." -ForegroundColor Green
