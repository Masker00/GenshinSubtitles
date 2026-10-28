# UI-thread coordinator. The worker never accesses WinForms controls or config.
function Get-ScanStamp([object]$Bounds) {
    $data = Get-Item -LiteralPath (Join-Path $root $db)
    $rect = Get-CropRectangle $Bounds
    return "$($config.RecognitionLanguage)|$($Bounds.ProcessId)|$($Bounds.Handle)|$($rect.X),$($rect.Y),$($rect.Width),$($rect.Height)|$($data.Length)|$($data.LastWriteTimeUtc.Ticks)"
}
function Stop-ScanWorker {
    if ($state.Worker) { $state.Worker.Dispose(); $state.Worker = $null }
    foreach ($path in @($state.RequestPath,$state.ImagePath)) {
        if ($path -and (Test-Path -LiteralPath $path)) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    }
    $state.RequestPath = $null; $state.ImagePath = $null
}
function Reset-ScanState {
    $state.Generation++
    Stop-ScanWorker
    $state.ScanStamp = ''; $state.LastLookup = ''; $state.LastSource = ''; $state.LastOpposite = ''; $state.LastOcr = ''
    $state.Cache = $null; $state.Misses = 0
    Set-Subtitle ''
}
function Start-ScanWorker([object]$Bounds, [string]$Stamp) {
    if ($state.Worker) { return } # no queue, no overlap
    $base = Join-Path ([IO.Path]::GetTempPath()) ('genshin-scan-' + [Guid]::NewGuid().ToString('N'))
    $state.ImagePath = $base + '.png'; $state.RequestPath = $base + '.json'
    $rect = Get-CropRectangle $Bounds
    $cache = if ($state.Cache -and [DateTime]::UtcNow -lt $state.CacheUntil) { $state.Cache } else { $null }
    $payload = @{
        ImagePath=$state.ImagePath; Python=$python; Source=$config.RecognitionLanguage; Cache=$cache
        Frame=@{ X=$rect.X; Y=$rect.Y; Width=$rect.Width; Height=$rect.Height }
        WindowHandle=[long]$Bounds.Handle; GameProcessId=[int]$Bounds.ProcessId
        GameBounds=@{ Left=$Bounds.Left; Top=$Bounds.Top; Right=$Bounds.Right; Bottom=$Bounds.Bottom }
    }
    [IO.File]::WriteAllText($state.RequestPath, ($payload | ConvertTo-Json -Compress -Depth 5), (New-Object Text.UTF8Encoding($false)))
    $shell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    try { $state.Worker = [SubtitleScanJob]::Start($shell, (Join-Path $root 'scan-worker.ps1'), $state.RequestPath, $Stamp, $state.Generation, 15) }
    catch { Stop-ScanWorker; throw }
}
function Receive-ScanResult([object]$Result, [int]$Generation, [string]$Stamp) {
    if (!$state.Enabled -or $settingsForm.Visible -or $Generation -ne $state.Generation -or $Stamp -ne $state.ScanStamp) { return $false }
    $text = [string]$Result.text
    if (!$text -or (Get-VisibleLength $text) -le 10) {
        $state.Misses++
        $ocrStatus.Text = if ($text) { (Get-UiText 'OcrShort') + ': ' + $text } else { Get-UiText 'OcrNoText' }
        if ($state.Misses -ge 4) { Clear-DisplayedResult }
        return $true
    }
    $state.Misses = 0
    $state.LastOcr = $text; $state.LastLookup = $text
    $state.LastSource = if ($Result.matched) { [string]$Result.source } else { $text }
    $state.LastOpposite = if ($Result.matched) { [string]$Result.opposite } else { '' }
    if (!$Result.cached) {
        $state.Cache = @{ Text=$text; Source=$config.RecognitionLanguage; Matched=[bool]$Result.matched; SourceText=[string]$Result.source; Opposite=[string]$Result.opposite; TextId=$Result.text_id; Method=[string]$Result.method; Similarity=[double]$Result.similarity }
        $state.CacheUntil = [DateTime]::UtcNow.AddSeconds(30)
    }
    $state.LastTextAt = [DateTime]::UtcNow
    $oppositeLanguage = if ($config.RecognitionLanguage -eq 'EN') { 'ZH' } else { 'EN' }
    $ocrStatus.Text = 'OCR (' + $config.RecognitionLanguage + '): ' + $text + [Environment]::NewLine +
        (Get-UiText 'Official') + ' ' + (Get-LanguageName $oppositeLanguage) + ': ' + $(if ($state.LastOpposite) { $state.LastOpposite } else { Get-UiText 'NoMatch' })
    Set-Subtitle (Get-CurrentSubtitleText)
    return $true
}
function Clear-DisplayedResult {
    $state.LastSource=''; $state.LastOpposite=''; $state.LastOcr=''
    Set-Subtitle ''
}
function Complete-ScanWorker {
    $worker = $state.Worker
    if (!$worker) { return }
    if (!$worker.Completed) {
        if ($worker.TimedOut) { Stop-ScanWorker; throw 'OCR worker timed out; automatic retry follows.' }
        return
    }
    try {
        if ($worker.ExitCode -ne 0) { throw ('OCR worker failed: ' + $worker.Error.Trim()) }
        $result = $worker.Output | ConvertFrom-Json
        [void](Receive-ScanResult $result $worker.Generation $worker.Stamp)
    } finally { Stop-ScanWorker }
}
function Invoke-ScanTick {
    try {
        if (!$state.Enabled -or $settingsForm.Visible) {
            if ($state.Worker) { Reset-ScanState }
            return
        }
        $bounds = Get-GameBounds
        if (!$bounds) {
            if (!$state.GameUnavailable -or $state.Worker -or $state.LastOcr) { Reset-ScanState }
            $state.GameUnavailable=$true; $ocrStatus.Text=Get-UiText 'GameUnavailable'
            $toolbarTips.SetToolTip($btnToggle, (Get-UiText 'GameUnavailable'))
            return
        }
        $stamp = Get-ScanStamp $bounds
        if ($state.GameUnavailable -or ($state.ScanStamp -and $stamp -ne $state.ScanStamp)) { Reset-ScanState }
        $state.GameUnavailable=$false; $state.LastBounds=$bounds; $state.ScanStamp=$stamp
        $toolbarTips.SetToolTip($btnToggle, '')
        Update-Layout $bounds
        Complete-ScanWorker
        if ($state.LastOcr -and ([DateTime]::UtcNow - $state.LastTextAt).TotalSeconds -ge 6) { Clear-DisplayedResult }
        if (!$state.Worker -and [DateTime]::UtcNow -ge $state.NextScanAt) {
            $state.NextScanAt=[DateTime]::UtcNow.AddMilliseconds(700)
            Start-ScanWorker $bounds $stamp
        }
    } catch {
        Stop-ScanWorker
        $ocrStatus.Text=(Get-UiText 'OcrError') + ': ' + $_.Exception.Message
        $state.NextScanAt=[DateTime]::UtcNow.AddSeconds(2)
        Clear-DisplayedResult
        try { Add-Content -LiteralPath (Join-Path $root 'overlay-errors.log') -Value ((Get-Date -Format o) + ' ' + $_.Exception.Message) } catch {}
    }
}
function Set-OverlayEnabled([bool]$Enabled) {
    $state.Enabled=$Enabled
    Update-Buttons
    if (!$Enabled) { Reset-ScanState }
}
function Invoke-OverlayHotkeys([bool]$Toggle, [bool]$Language) {
    if ($Toggle -and !$state.HotkeyToggle) { Set-OverlayEnabled (!$state.Enabled) }
    if ($Language -and !$state.HotkeyLanguage) { Switch-SubtitleLanguage }
    $state.HotkeyToggle=$Toggle; $state.HotkeyLanguage=$Language
}
function Start-OverlayRuntime {
    $hotkeyTimer=New-Object System.Windows.Forms.Timer
    $hotkeyTimer.Interval=45
    $hotkeyTimer.Add_Tick({
        $ctrl=(([GenshinSubtitleOverlayNative]::GetAsyncKeyState(0x11) -band 0x8000) -ne 0)
        $shift=(([GenshinSubtitleOverlayNative]::GetAsyncKeyState(0x10) -band 0x8000) -ne 0)
        Invoke-OverlayHotkeys ($ctrl -and $shift -and (([GenshinSubtitleOverlayNative]::GetAsyncKeyState(0x54) -band 0x8000) -ne 0)) ($ctrl -and $shift -and (([GenshinSubtitleOverlayNative]::GetAsyncKeyState(0x59) -band 0x8000) -ne 0))
    })
    $scanTimer=New-Object System.Windows.Forms.Timer
    $scanTimer.Interval=100
    $scanTimer.Add_Tick({ Invoke-ScanTick })
    $hotkeyTimer.Start(); $scanTimer.Start()
    try { [System.Windows.Forms.Application]::Run() }
    finally { $hotkeyTimer.Stop(); $scanTimer.Stop(); $hotkeyTimer.Dispose(); $scanTimer.Dispose(); Stop-ScanWorker }
}
$state.Worker=$null; $state.Generation=0; $state.ScanStamp=''; $state.Cache=$null; $state.GameUnavailable=$false
$state.CacheUntil=[DateTime]::MinValue; $state.NextScanAt=[DateTime]::MinValue; $state.LastTextAt=[DateTime]::MinValue
$state.HotkeyToggle=$false; $state.HotkeyLanguage=$false
