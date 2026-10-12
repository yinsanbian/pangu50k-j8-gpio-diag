param([int]$TimeoutSec = 900)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pdsFile = Join-Path $projectRoot 'pds\pangu50k_j8_gpio_diag.pds'
if (-not (Test-Path -LiteralPath $pdsFile -PathType Leaf)) { throw "Project missing: $pdsFile" }
$argsFile = Join-Path $PSScriptRoot 'pds_build.json'
@{
  pdsPath = $pdsFile
  timeoutSec = $TimeoutSec
  cache = $false
  backupOldBuildDirs = $false
  detail = 'full'
} | ConvertTo-Json | Set-Content -LiteralPath $argsFile -Encoding utf8NoBOM
& node (Join-Path $PSScriptRoot 'configure_bitstream.mjs')
if ($LASTEXITCODE -ne 0) { throw 'Cannot configure bitstream options.' }
& node (Join-Path $PSScriptRoot 'pango_call.mjs') fpga_pds_compile $argsFile
if ($LASTEXITCODE -ne 0) { throw 'PDS implementation failed. See reports/mcp.' }
& node (Join-Path $PSScriptRoot 'audit_io.mjs')
if ($LASTEXITCODE -ne 0) { throw 'PDS IO pin audit failed.' }
& node (Join-Path $PSScriptRoot 'collect_pds_evidence.mjs')
if ($LASTEXITCODE -ne 0) { throw 'PDS evidence validation failed.' }
