# Runs inside the overlay UI check with its isolated settings.
$settingsForm.Hide()
Reset-ScanState
$state.ScanStamp='test-context'
$sample=[pscustomobject]@{text='Observed sample longer than ten characters';matched=$true;source='Official sample source';opposite='Official opposite sample';text_id='test';method='exact';similarity=1.0;cached=$false}
$generation=$state.Generation
if (!(Receive-ScanResult $sample $generation 'test-context')) { throw 'Current result rejected.' }
Update-OverlayConfig @{RecognitionLanguage='ZH'} $false
if (Receive-ScanResult $sample $generation 'test-context') { throw 'Old language result was applied.' }
$state.ScanStamp='test-context'; $generation=$state.Generation
Update-OverlayConfig @{Left=20.0} $false
if (Receive-ScanResult $sample $generation 'test-context') { throw 'Old region result was applied.' }
$state.ScanStamp='test-context'; $generation=$state.Generation
$settingsForm.Show()
if (Receive-ScanResult $sample $generation 'test-context') { throw 'Result was applied during SET.' }
Invoke-ScanTick
if ($state.Worker) { throw 'SET started an automatic scan.' }
$settingsForm.Hide()
$state.ScanStamp='test-context'; $generation=$state.Generation
$btnToggle.PerformClick()
if ($state.Enabled -or (Receive-ScanResult $sample $generation 'test-context')) { throw 'Stopped result was applied.' }
Invoke-OverlayHotkeys $true $false
if (!$state.Enabled) { throw 'Toggle shortcut failed.' }
Invoke-OverlayHotkeys $true $false
if (!$state.Enabled) { throw 'Held shortcut toggled repeatedly.' }
Invoke-OverlayHotkeys $false $false
$wasEnabled=$state.Enabled
Set-ToolbarCollapsed $true $false
Invoke-OverlayHotkeys $true $false
if ($state.Enabled -eq $wasEnabled) { throw 'Collapsed toolbar blocked toggle shortcut.' }
Invoke-OverlayHotkeys $false $false
Invoke-OverlayHotkeys $true $false
Invoke-OverlayHotkeys $false $false
Set-ToolbarCollapsed $false $false
$before=$state.Language
Invoke-OverlayHotkeys $false $true
if ($state.Language -eq $before -or $config.SubtitleLanguage -ne $state.Language) { throw 'Language shortcut failed to update config.' }
Invoke-OverlayHotkeys $false $false
$state.ScanStamp='new-database-version'
if (Receive-ScanResult $sample $state.Generation 'old-database-version') { throw 'Old data result was applied.' }
$gameBoundsFunction=(Get-Command Get-GameBounds).ScriptBlock
try {
    function Get-GameBounds { return $null }
    $state.LastOcr='obsolete'; $state.LastSource='obsolete'; Set-Subtitle 'obsolete'
    Invoke-ScanTick
    if ($subtitle.Visible -or $state.LastSource -or $state.Worker -or !$state.GameUnavailable) { throw 'Missing/minimized window did not pause and clear.' }
} finally { Set-Item Function:Get-GameBounds $gameBoundsFunction }
Write-Output 'Stale results, SET pause, stop, shortcuts and missing window clearing: OK'
$fixture=Join-Path $root ('test-results/delayed-ui-worker-' + [Guid]::NewGuid().ToString('N') + '.ps1')
[IO.File]::WriteAllText($fixture, 'param([string]$WorkerRequest) Start-Sleep -Seconds 30; [Console]::Out.WriteLine(''{"matched":false}'')')
try {
    $shell=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $state.Worker=[SubtitleScanJob]::Start($shell,$fixture,'unused','pending',$state.Generation,10)
    $firstPid=$state.Worker.ProcessId
    Start-ScanWorker $null 'must-not-queue'
    if ($state.Worker.ProcessId -ne $firstPid) { throw 'Busy scanner started a second worker.' }
    $before=$state.Language
    $btnLang.PerformClick()
    if ($before -eq $state.Language -or $state.Worker.Completed) { throw 'UI did not respond during active scan.' }
    Update-OverlayConfig @{RecognitionLanguage=$(if ($config.RecognitionLanguage -eq 'ZH') {'EN'} else {'ZH'})} $false
    if ($state.Worker -or (Get-Process -Id $firstPid -ErrorAction SilentlyContinue)) { throw 'Recognition change did not cancel the worker.' }
    $state.Worker=[SubtitleScanJob]::Start($shell,$fixture,'unused','exit',$state.Generation,10)
    $exitPid=$state.Worker.ProcessId
    $toolbar.Close()
    if ($state.Worker -or (Get-Process -Id $exitPid -ErrorAction SilentlyContinue)) { throw 'Exit left the worker running.' }
    Write-Output 'Active-scan UI controls, one-worker limit, cancellation and toolbar exit cleanup: OK'
} finally {
    Stop-ScanWorker
    Remove-Item -LiteralPath $fixture -Force
}
