param(
    [ValidateSet('all','core','uart','report','production')]
    [string]$Test = 'all'
)
$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$client = Join-Path $projectRoot 'scripts/pango_call.mjs'
$reportRoot = Join-Path $projectRoot 'reports'
$argRoot = Join-Path $reportRoot 'sim_args'
New-Item -ItemType Directory -Path $argRoot -Force | Out-Null
$tests = if ($Test -eq 'all') { @('core','uart','report','production') } else { @($Test) }
foreach ($kind in $tests) {
    $rtlNames = if ($kind -eq 'core') {
        @('error_counter.v','gpio_pair_mux.v','gpio_test_ctrl.v')
    } elseif ($kind -eq 'report') {
        @('uart_tx.v','uart_report.v')
    } else {
        @('reset_sync.v','error_counter.v','gpio_pair_mux.v','gpio_test_ctrl.v',
          'uart_rx.v','uart_tx.v','diag_command.v','uart_report.v','gpio_diag_top.v')
    }
    $sourceFiles = @($rtlNames | ForEach-Object { Join-Path $projectRoot "rtl/$_" })
    $topName = if ($kind -eq 'report') { 'tb_uart_report' } else { "tb_gpio_$kind" }
    $passMarker = if ($kind -eq 'report') { 'TB_PASS uart_report' } else { "TB_PASS gpio_$kind" }
    $resultName = if ($kind -eq 'report') { 'sim_uart_report' } else { "sim_gpio_$kind" }
    $tbFile = if ($kind -eq 'production') {
        Join-Path $PSScriptRoot 'tb/production/tb_gpio_production.sv'
    } else {
        Join-Path $PSScriptRoot "tb/$topName.sv"
    }
    $sourceFiles += $tbFile
    $arguments = @{
        workdir = $PSScriptRoot
        top = $topName
        sources = $sourceFiles
        runArg = '-all'
        cache = $false
        vcd = $false
        assertions = @(
            @{ type='log_contains'; value=$passMarker },
            @{ type='log_not_contains'; value='TB_FAIL' }
        )
        timeoutSec = 300
        detail = 'full'
    }
    $argumentFile = Join-Path $argRoot "$kind.json"
    $arguments | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $argumentFile -Encoding utf8
    Write-Host "Running $kind self-check through pango-mcp / ModelSim"
    $output = (& node $client 'fpga_msim_sim' $argumentFile | Out-String)
    $exitCode = $LASTEXITCODE
    $result = $output | ConvertFrom-Json
    $output | Set-Content -LiteralPath (Join-Path $reportRoot "$resultName.result.json") -Encoding utf8
    if ($result.artifacts.log) {
        Copy-Item -LiteralPath $result.artifacts.log -Destination (Join-Path $reportRoot "$resultName.log") -Force
    }
    if ($result.artifacts.compileLog) {
        Copy-Item -LiteralPath $result.artifacts.compileLog -Destination (Join-Path $reportRoot "compile_gpio_$kind.log") -Force
    }
    if ($exitCode -ne 0 -or !$result.ok -or !$result.assert.ok) {
        throw "The $kind self-check failed. Inspect reports/sim_gpio_$kind.result.json"
    }
    Write-Host "$kind : PASS"
}
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'uart_observed.txt')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'uart_observed.txt') -Destination (Join-Path $reportRoot 'uart_observed.txt') -Force
}
