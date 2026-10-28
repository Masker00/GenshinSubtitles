if (!$settingsExistedAtStartup -and !$freshDefaultsApplied) { throw ('Fresh-start defaults do not match the requested layout and languages: ' + ($config | ConvertTo-Json -Compress)) }
function Send-ToolbarMouse([int]$Message, [int]$X, [int]$Y) {
    $packed = ($X -band 0xffff) -bor (($Y -band 0xffff) -shl 16)
    [void][GenshinSubtitleOverlayNative]::SendMessage($toolbar.Handle, $Message, [IntPtr]::new(1), [IntPtr]::new($packed))
}
Write-Output 'UI: toolbar'
Set-ToolbarCollapsed $false $false
$toolbar.Location = [Drawing.Point]::new($toolbar.MovementBounds.Left + 700, $toolbar.MovementBounds.Top + 700)
Save-ToolbarPosition
Write-Output 'UI: toolbar settings saved'
$beforeToolbar = $toolbar.Location
Write-Output 'UI: toolbar mouse down'
Send-ToolbarMouse 0x201 10 20
Write-Output 'UI: toolbar mouse move'
Send-ToolbarMouse 0x200 70 50
Send-ToolbarMouse 0x202 10 20
Update-Layout $state.LastBounds
if ([Math]::Abs($toolbar.Left - $beforeToolbar.X - 60) -gt 1 -or [Math]::Abs($toolbar.Top - $beforeToolbar.Y - 30) -gt 1) {
    throw 'Toolbar drag or retained position failed.'
}
$btnHide.PerformClick()
if (!$toolbar.Collapsed -or $toolbar.Width -ne 40 -or $btnToggle.Visible) { throw 'Toolbar did not collapse to an icon.' }
$beforeToolbar = $toolbar.Location
Send-ToolbarMouse 0x201 20 20
Send-ToolbarMouse 0x200 50 40
Send-ToolbarMouse 0x202 20 20
Update-Layout $state.LastBounds
if (!$toolbar.Collapsed -or [Math]::Abs($toolbar.Left - $beforeToolbar.X - 30) -gt 1 -or [Math]::Abs($toolbar.Top - $beforeToolbar.Y - 20) -gt 1) {
    throw 'Collapsed icon drag unexpectedly restored the toolbar or lost position.'
}
$toolbarSnapshot = [Drawing.Bitmap]::new($toolbar.Width, $toolbar.Height)
try {
    $toolbar.DrawToBitmap($toolbarSnapshot, [Drawing.Rectangle]::new(0, 0, $toolbar.Width, $toolbar.Height))
    $toolbarSnapshot.Save((Join-Path $root 'test-results/toolbar-icon-check.png'), [Drawing.Imaging.ImageFormat]::Png)
} finally { $toolbarSnapshot.Dispose() }
$savedToolbar = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json
if (!$savedToolbar.ToolbarCollapsed -or $savedToolbar.ToolbarLeft -ne $config.ToolbarLeft -or $savedToolbar.ToolbarTop -ne $config.ToolbarTop) {
    throw 'Toolbar collapsed state and position were not saved.'
}
Send-ToolbarMouse 0x201 20 20
Send-ToolbarMouse 0x202 20 20
if ($toolbar.Collapsed -or !$btnToggle.Visible -or $toolbar.Width -ne 360) { throw 'Icon click did not restore the toolbar.' }
$toolbarSnapshot = [Drawing.Bitmap]::new($toolbar.Width, $toolbar.Height)
try {
    $toolbar.DrawToBitmap($toolbarSnapshot, [Drawing.Rectangle]::new(0, 0, $toolbar.Width, $toolbar.Height))
    $toolbarSnapshot.Save((Join-Path $root 'test-results/toolbar-layout-check.png'), [Drawing.Imaging.ImageFormat]::Png)
} finally { $toolbarSnapshot.Dispose() }
$frameHiddenOutsideSettings = !$cropFrame.Visible
$transparentSubtitle = $subtitle.Opacity -eq 1.0 -and $subtitle.TransparencyKey.ToArgb() -eq [Drawing.Color]::Magenta.ToArgb()
Write-Output 'UI: settings selections'
$settingsForm.Show()
[System.Windows.Forms.Application]::DoEvents()
$frameVisibleInSettings = $cropFrame.Visible
$dragEnabledInSettings = $selection.Visible -and $selection.TransparencyKey.IsEmpty -and $selection.Controls.Count -eq 0
function Send-SelectionMouse([int]$Message, [int]$X, [int]$Y) {
    $packed = ($X -band 0xffff) -bor (($Y -band 0xffff) -shl 16)
    [void][GenshinSubtitleOverlayNative]::SendMessage($selection.Handle, $Message, [IntPtr]::new(1), [IntPtr]::new($packed))
}
$testLeft = $selection.MovementBounds.Left + 550
$testTop = $selection.MovementBounds.Top + 250
$selection.Bounds = [Drawing.Rectangle]::new($testLeft, $testTop, 600, 240)
Sync-SubtitleSelection
$before = $selection.Bounds
$hitPoint = [Drawing.Point]::new($selection.Left + 100, $selection.Top + 80)
if ([GenshinSubtitleOverlayNative]::WindowFromPoint($hitPoint) -ne $selection.Handle) {
    throw 'The selection interior is not receiving desktop mouse hit tests.'
}
Send-SelectionMouse 0x201 100 80
Send-SelectionMouse 0x200 140 110
Send-SelectionMouse 0x202 100 80
if ([Math]::Abs($selection.Left - $before.Left - 40) -gt 1 -or [Math]::Abs($selection.Top - $before.Top - 30) -gt 1) {
    throw ('Mouse messages did not move the selection: ' + $before.ToString() + ' -> ' + $selection.Bounds.ToString())
}
# Exercise all four edges and four corners through the actual window mouse events.
foreach ($edge in @(1, 2, 4, 8, 5, 6, 9, 10)) {
    $selection.Bounds = [Drawing.Rectangle]::new($testLeft, $testTop, 600, 240)
    Sync-SubtitleSelection
    $before = $selection.Bounds
    $x = if ($edge -band 1) { 2 } elseif ($edge -band 2) { $selection.Width - 2 } else { 100 }
    $y = if ($edge -band 4) { 2 } elseif ($edge -band 8) { $selection.Height - 2 } else { 80 }
    $dx = if ($edge -band 1) { -30 } elseif ($edge -band 2) { 30 } else { 0 }
    $dy = if ($edge -band 4) { -20 } elseif ($edge -band 8) { 20 } else { 0 }
    Send-SelectionMouse 0x201 $x $y
    Send-SelectionMouse 0x200 ($x + $dx) ($y + $dy)
    Send-SelectionMouse 0x202 $x $y
    $expectedW = $before.Width + [Math]::Abs($dx)
    $expectedH = $before.Height + [Math]::Abs($dy)
    if ([Math]::Abs($selection.Width - $expectedW) -gt 1 -or [Math]::Abs($selection.Height - $expectedH) -gt 1) {
        throw "Selection resize failed for edge $edge."
    }
}
$persisted = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json
$dragPositionSaved = $persisted.DisplayLeft -eq $config.DisplayLeft -and $persisted.DisplayTop -eq $config.DisplayTop -and $persisted.DisplayWidth -eq $config.DisplayWidth -and $persisted.DisplayHeight -eq $config.DisplayHeight
function Send-CropMouse([int]$Message, [int]$X, [int]$Y) {
    $packed = ($X -band 0xffff) -bor (($Y -band 0xffff) -shl 16)
    [void][GenshinSubtitleOverlayNative]::SendMessage($cropFrame.Handle, $Message, [IntPtr]::new(1), [IntPtr]::new($packed))
}
$cropFrame.BringToFront()
$testLeft = $cropFrame.MovementBounds.Left + 550
$testTop = $cropFrame.MovementBounds.Top + 250
$cropFrame.Bounds = [Drawing.Rectangle]::new($testLeft, $testTop, 600, 240)
Sync-CropSelection
$before = $cropFrame.Bounds
$hitPoint = [Drawing.Point]::new($cropFrame.Left + 100, $cropFrame.Top + 80)
if ([GenshinSubtitleOverlayNative]::WindowFromPoint($hitPoint) -ne $cropFrame.Handle) {
    throw 'The selection interior is not receiving desktop mouse hit tests.'
}
Send-CropMouse 0x201 100 80
Send-CropMouse 0x200 140 110
Send-CropMouse 0x202 100 80
if ([Math]::Abs($cropFrame.Left - $before.Left - 40) -gt 1 -or [Math]::Abs($cropFrame.Top - $before.Top - 30) -gt 1) {
    throw ('Mouse messages did not move the selection: ' + $before.ToString() + ' -> ' + $cropFrame.Bounds.ToString())
}
# Exercise all four edges and four corners through the actual window mouse events.
foreach ($edge in @(1, 2, 4, 8, 5, 6, 9, 10)) {
    $cropFrame.Bounds = [Drawing.Rectangle]::new($testLeft, $testTop, 600, 240)
    Sync-CropSelection
    $before = $cropFrame.Bounds
    $x = if ($edge -band 1) { 2 } elseif ($edge -band 2) { $cropFrame.Width - 2 } else { 100 }
    $y = if ($edge -band 4) { 2 } elseif ($edge -band 8) { $cropFrame.Height - 2 } else { 80 }
    $dx = if ($edge -band 1) { -30 } elseif ($edge -band 2) { 30 } else { 0 }
    $dy = if ($edge -band 4) { -20 } elseif ($edge -band 8) { 20 } else { 0 }
    Send-CropMouse 0x201 $x $y
    Send-CropMouse 0x200 ($x + $dx) ($y + $dy)
    Send-CropMouse 0x202 $x $y
    $expectedW = $before.Width + [Math]::Abs($dx)
    $expectedH = $before.Height + [Math]::Abs($dy)
    if ([Math]::Abs($cropFrame.Width - $expectedW) -gt 1 -or [Math]::Abs($cropFrame.Height - $expectedH) -gt 1) {
        throw "Selection resize failed for edge $edge."
    }
}
$persisted = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json
$cropPositionSaved = $persisted.Left -eq $config.Left -and $persisted.Top -eq $config.Top -and $persisted.Width -eq $config.Width -and $persisted.Height -eq $config.Height
if (!$cropPositionSaved) { throw 'OCR selection position and size were not saved.' }
$cropSnapshot = [Drawing.Bitmap]::new($cropFrame.Width, $cropFrame.Height)
try {
    $cropFrame.DrawToBitmap($cropSnapshot, [Drawing.Rectangle]::new(0, 0, $cropFrame.Width, $cropFrame.Height))
    $cropSnapshot.Save((Join-Path $root 'test-results/ocr-selection-check.png'), [Drawing.Imaging.ImageFormat]::Png)
} finally { $cropSnapshot.Dispose() }
$settingsForm.Hide()
[System.Windows.Forms.Application]::DoEvents()
$frameHiddenAfterSettings = !$cropFrame.Visible
$dragDisabledAfterSettings = $subtitle.ClickThrough -and !$selection.Visible
Write-Output 'UI: settings selections'
$settingsForm.Show()
[System.Windows.Forms.Application]::DoEvents()
if (!$frameHiddenOutsideSettings -or !$frameVisibleInSettings -or !$frameHiddenAfterSettings -or !$dragEnabledInSettings -or !$dragDisabledAfterSettings -or !$dragPositionSaved -or !$transparentSubtitle) {
    throw 'Frame visibility, transparent subtitle style, or settings-only drag behavior is incorrect.'
}
$settingDisplayLeft.Value = 5; $settingDisplayWidth.Value = 90
$settingDisplayHeight.Value = 18
$settingRecognitionLanguage.SelectedIndex = 0
$settingSubtitleLanguage.SelectedIndex = 1
$originalX = $cropFrame.Left
$settingLeft.Value = [int]$settingLeft.Value + $(if ($settingLeft.Value -lt 95) { 1 } else { -1 })
$positionChanged = $cropFrame.Left -ne $originalX
$settingFont.Value = [int]$settingFont.Value + $(if ($settingFont.Value -lt 48) { 1 } else { -1 })
$fontChanged = $label.Font.Size -eq $settingFont.Value
$previousSubtitleWidth = $subtitle.Width
$settingDisplayWidth.Value = [int]$settingDisplayWidth.Value + $(if ($settingDisplayWidth.Value -lt $settingDisplayWidth.Maximum) { 1 } else { -1 })
$displayWidthChanged = $subtitle.Width -ne $previousSubtitleWidth
$frameScreenBounds = Get-CropFrameScreenBounds
$captureBounds = Get-CaptureRectangle $frameScreenBounds
if (!$positionChanged -or !$fontChanged -or !$displayWidthChanged -or $captureBounds.Left -ne ($frameScreenBounds.Left + 5) -or $captureBounds.Top -ne ($frameScreenBounds.Top + 5)) { throw 'Settings controls or OCR crop bounds are incorrect.' }
$state.LastOcr = '测试中文字幕超过十个字符'
$state.LastSource = '官方中文字幕示例。'
$state.LastOpposite = 'An official English subtitle example.'
$btnLang.PerformClick()
$zhWorks = $state.Language -eq 'ZH' -and $label.Text -eq $state.LastSource
$btnLang.PerformClick()
$enWorks = $state.Language -eq 'EN' -and $label.Text -eq $state.LastOpposite
if (!$zhWorks -or !$enWorks) { throw 'Language button did not switch both subtitle texts.' }
$settingRecognitionLanguage.SelectedIndex = 1
$recognitionSwitchWorks = $config.RecognitionLanguage -eq 'EN' -and $state.Language -eq 'EN' -and !$state.LastOcr
if (!$recognitionSwitchWorks) { throw 'OCR recognition language did not switch independently.' }
$state.LastOcr = 'Observed English subtitle text.'
$state.LastSource = 'Official English subtitle sample.'
$state.LastOpposite = '官方中文字幕示例。'
$btnLang.PerformClick()
$zhOfficialWorks = $state.Language -eq 'ZH' -and $label.Text -eq $state.LastOpposite
$btnLang.PerformClick()
$enOfficialWorks = $state.Language -eq 'EN' -and $label.Text -eq $state.LastSource
if (!$enOfficialWorks -or !$zhOfficialWorks) { throw 'English recognition language did not switch both official subtitle texts.' }
$settingPluginLanguage.SelectedIndex = 1
$englishUiWorks = $config.PluginLanguage -eq 'EN' -and $settingsForm.Text -eq 'Subtitle settings' -and $settingRecognitionLanguage.Items[1] -eq 'English'
$settingPluginLanguage.SelectedIndex = 0
$chineseUiWorks = $config.PluginLanguage -eq 'ZH' -and $settingsForm.Text -eq '字幕设置' -and $settingRecognitionLanguage.Items[1] -eq '英文'
if (!$englishUiWorks -or !$chineseUiWorks) { throw 'Plugin language did not update the interface.' }
Write-Output 'UI: lookup'
$realLookup = Lookup-Official 'But for now, all yo u need to remember is this: If yo u collect Kresnik KristaII, can extract' 'EN'
if (!$realLookup.opposite.Contains(([string][char]0x514B + [char]0x4EC0 + [char]0x5C3C + [char]0x514B)) -or !$realLookup.source.StartsWith('But for now')) { throw 'PowerShell English-to-Chinese official lookup failed.' }
$resetSettings.PerformClick()
$defaultsWork = $config.Left -eq 16.5 -and $config.Top -eq 84 -and $config.Width -eq 67 -and $config.Height -eq 9.5 -and
    $config.FontSize -eq 24 -and $config.DisplayLeft -eq 16.5 -and $config.DisplayTop -eq 93.5 -and $config.DisplayWidth -eq 67 -and
    $config.DisplayHeight -eq 5.5 -and $config.TextPadding -eq 16 -and $config.PluginLanguage -eq 'ZH' -and
    $config.RecognitionLanguage -eq 'EN' -and $config.SubtitleLanguage -eq 'EN'
if (!$defaultsWork) { throw 'Reset did not restore the requested layout and language defaults.' }
$longText = 'But for now, all you need to remember is this: If you collect Kresnik Kristall, I can extract the energy within and keep your body temperature stable. Remember that before we move on.'
Set-Subtitle $longText
$contentWidth = $subtitle.Width - 2 * $config.TextPadding
$contentHeight = $subtitle.Height - 2 * $config.TextPadding
$flags = [System.Windows.Forms.TextFormatFlags]::WordBreak -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix -bor [System.Windows.Forms.TextFormatFlags]::NoPadding
$measured = [System.Windows.Forms.TextRenderer]::MeasureText($label.Text, $label.Font, [Drawing.Size]::new($contentWidth, 10000), $flags)
$longTextFits = !$label.AutoEllipsis -and $label.Text -eq $longText -and $measured.Height -le $contentHeight
if (!$longTextFits) { throw 'Long subtitle does not fit in the display area.' }
$subtitleSnapshot = [Drawing.Bitmap]::new($subtitle.Width, $subtitle.Height)
try {
    $subtitle.DrawToBitmap($subtitleSnapshot, [Drawing.Rectangle]::new(0, 0, $subtitle.Width, $subtitle.Height))
    $subtitleSnapshot.Save((Join-Path $root 'test-results/subtitle-layout-check.png'), [Drawing.Imaging.ImageFormat]::Png)
} finally { $subtitleSnapshot.Dispose() }
$settingsTabs.SelectedTab = $displayTab
$settingsSnapshot = [Drawing.Bitmap]::new($settingsForm.Width, $settingsForm.Height)
try {
    $settingsForm.DrawToBitmap($settingsSnapshot, [Drawing.Rectangle]::new(0, 0, $settingsForm.Width, $settingsForm.Height))
    $settingsSnapshot.Save((Join-Path $root 'test-results/settings-layout-check.png'), [Drawing.Imaging.ImageFormat]::Png)
} finally { $settingsSnapshot.Dispose() }
$settingsTabs.SelectedTab = $ocrTab
$ocrSettingsSnapshot = [Drawing.Bitmap]::new($settingsForm.Width, $settingsForm.Height)
try {
    $settingsForm.DrawToBitmap($ocrSettingsSnapshot, [Drawing.Rectangle]::new(0, 0, $settingsForm.Width, $settingsForm.Height))
    $ocrSettingsSnapshot.Save((Join-Path $root 'test-results/ocr-settings-layout-check.png'), [Drawing.Imaging.ImageFormat]::Png)
} finally { $ocrSettingsSnapshot.Dispose() }
[pscustomobject]@{
    toolbar_buttons = $toolbar.Controls.Count
    toolbar_drag_collapse_restore = 'ok'
    settings_controls = $settingsForm.Controls.Count
    crop_bounds = $cropFrame.Bounds.ToString()
    frame_screen_bounds = $frameScreenBounds.ToString()
    crop_visible = $cropFrame.Visible
    frame_settings_only = 'ok'
    transparent_subtitle = 'ok'
    drag_position_save = 'ok'
    mouse_move_and_eight_resize_handles = 'ok'
    ocr_move_eight_resize_and_save = 'ok'
    desktop_mouse_hit_test = 'ok'
    font_size = $label.Font.Size
    setting_events = 'ok'
    language_button = 'ok'
    recognition_and_output_language = 'ok'
    plugin_language = 'ok'
    requested_defaults = 'ok'
    fresh_start_defaults = $(if ($settingsExistedAtStartup) { 'not tested: existing settings loaded' } elseif ($freshDefaultsApplied) { 'ok' } else { 'failed' })
    english_to_chinese_lookup = 'ok'
    long_subtitle_fits = $longTextFits
    subtitle_bounds = $subtitle.Bounds.ToString()
    capture_bounds = $captureBounds.ToString()
} | ConvertTo-Json
. (Join-Path $root 'tests/runtime_ui_tests.ps1')
$settingsForm.Dispose()
$cropFrame.Dispose()
$subtitle.Dispose()
$toolbar.Dispose()
return
