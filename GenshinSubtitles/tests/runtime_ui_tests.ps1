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
