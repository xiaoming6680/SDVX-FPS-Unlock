# Builds dist\SDVX-FPS-Unlock-<version>.zip containing only the files end users need.
param([Parameter(Mandatory = $true)][string]$Version)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$name = "SDVX-FPS-Unlock-$Version"
$stage = Join-Path $root "dist\$name"
$zip = Join-Path $root "dist\$name.zip"

if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
New-Item -ItemType Directory -Path $stage | Out-Null

Copy-Item -LiteralPath (Join-Path $root 'install.bat') -Destination $stage
Copy-Item -LiteralPath (Join-Path $root 'install.ps1') -Destination $stage
Copy-Item -LiteralPath (Join-Path $root 'release\README.txt') -Destination $stage

Compress-Archive -Path $stage -DestinationPath $zip
Remove-Item -LiteralPath $stage -Recurse -Force
Write-Host $zip
