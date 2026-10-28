$hotkeyTimer = New-Object System.Windows.Forms.Timer
$hotkeyTimer.Interval = 45
$hotkeyState = @{ Toggle = $false; Language = $false }
$hotkeyTimer.Add_Tick({
    $ctrl = (([GenshinSubtitleOverlayNative]::GetAsyncKeyState(0x11) -band 0x8000) -ne 0)
    $shift = (([GenshinSubtitleOverlayNative]::GetAsyncKeyState(0x10) -band 0x8000) -ne 0)
    $toggle = $ctrl -and $shift -and (([GenshinSubtitleOverlayNative]::GetAsyncKeyState(0x54) -band 0x8000) -ne 0)
    $language = $ctrl -and $shift -and (([GenshinSubtitleOverlayNative]::GetAsyncKeyState(0x59) -band 0x8000) -ne 0)
    if ($toggle -and !$hotkeyState.Toggle) { $state.Enabled = !$state.Enabled; Update-Buttons; if (!$state.Enabled) { Set-Subtitle '' } }
    if ($language -and !$hotkeyState.Language) { Switch-SubtitleLanguage }
    $hotkeyState.Toggle = $toggle
    $hotkeyState.Language = $language
})

$scanTimer = New-Object System.Windows.Forms.Timer
$scanTimer.Interval = 700
$scanTimer.Add_Tick({
    if ($state.Busy -or $settingsForm.Visible) { return }
    $state.Busy = $true
    try {
        $bounds = @(Get-GameBounds | Select-Object -Last 1)[0]
        $state.LastBounds = $bounds
        Update-Layout $bounds
        Capture-SubtitleRegion (Get-CropFrameScreenBounds) $tempImage
        $activeEngine = if ($config.RecognitionLanguage -eq 'EN') { if ($enEngine) { $enEngine } else { $zhEngine } } else { if ($zhEngine) { $zhEngine } else { $enEngine } }
        $ocrText = (Invoke-Ocr $tempImage $activeEngine).Trim()
        if (!$ocrText -or (Get-VisibleLength $ocrText) -le 10) {
            $ocrStatus.Text = if ($ocrText) { (Get-UiText 'OcrShort') + ': ' + $ocrText } else { Get-UiText 'OcrNoText' }
            $state.Misses++
            # Keep the last result through transient OCR misses. Clear only
            # after several consecutive misses, which prevents visible flicker.
            if ($state.Misses -ge 4) { Set-Subtitle '' }
            return
        }
        $state.Misses = 0
        if ($ocrText -ne $state.LastLookup) {
            $official = Lookup-Official $ocrText $config.RecognitionLanguage
            $state.LastSource = if ($official.source) { $official.source } else { $ocrText }
            $state.LastOpposite = $official.opposite
            $state.LastLookup = $ocrText
        }
        $state.LastOcr = $ocrText
        $oppositeLanguage = if ($config.RecognitionLanguage -eq 'EN') { 'ZH' } else { 'EN' }
        $ocrEngineName = if ($config.RecognitionLanguage -eq 'EN' -and !$enEngine) { 'EN via Chinese OCR' } else { $config.RecognitionLanguage }
        $ocrStatus.Text = 'OCR (' + $ocrEngineName + '): ' + $ocrText + [Environment]::NewLine + (Get-UiText 'Official') + ' ' + (Get-LanguageName $oppositeLanguage) + ': ' + $(if ($state.LastOpposite) { $state.LastOpposite } else { Get-UiText 'NoMatch' })
        Set-Subtitle (Get-CurrentSubtitleText)
    }
    catch {
        $ocrStatus.Text = (Get-UiText 'OcrError') + ': ' + $_.Exception.Message
        try {
            Add-Content -LiteralPath (Join-Path $root 'overlay-errors.log') -Value ((Get-Date -Format o) + ' ' + $_.Exception.ToString())
        } catch {}
        $state.Misses++
        if ($state.Misses -ge 4) { Set-Subtitle '' }
    }
    finally {
        $state.Busy = $false
    }
})
$hotkeyTimer.Start()
$scanTimer.Start()
[System.Windows.Forms.Application]::Run()
$hotkeyTimer.Stop()
$scanTimer.Stop()
if (Test-Path -LiteralPath $tempImage) { Remove-Item -LiteralPath $tempImage -Force -ErrorAction SilentlyContinue }
