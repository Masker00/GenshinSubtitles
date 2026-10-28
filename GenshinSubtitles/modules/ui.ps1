$uiStrings = @{
    EN = @{
        SettingsTitle = 'Subtitle settings'; OcrTab = 'OCR'; SubtitleTab = 'Subtitle'
        OcrLeft = 'OCR left (%)'; OcrTop = 'OCR top (%)'; OcrWidth = 'OCR width (%)'; OcrHeight = 'OCR height (%)'
        PluginLanguage = 'Plugin language'; RecognitionLanguage = 'Recognition language'; SubtitleLanguage = 'Subtitle language after recognition'
        Chinese = 'Chinese'; English = 'English'; MaxFontSize = 'Maximum font size'
        SubtitleLeft = 'Subtitle left (%)'; SubtitleTop = 'Subtitle top (%)'; SubtitleWidth = 'Subtitle width (%)'; SubtitleHeight = 'Subtitle height (%)'; TextPadding = 'Text padding (px)'
        DragHint = 'Drag inside the blue selection to move. Drag any edge or corner to resize. Release to save position and size.'
        ShowOcrSelection = 'Show draggable OCR selection'; OcrIdle = 'OCR: select Preview OCR crop to inspect the captured pixels'
        PreviewOcr = 'Preview OCR crop'; Reset = 'Reset'; Close = 'Close'; Settings = 'SET'; Exit = 'EXIT'
        HideToolbar = 'Hide toolbar'; DragToolbar = 'Drag to move'; ShowToolbar = 'Show toolbar; drag to move'
        DragSubtitle = 'Drag subtitle to position'; PreviewInput = 'Preview: actual OCR input'; PreviewError = 'Preview error'
        OcrNoText = 'OCR: no text in frame'; OcrShort = 'OCR (10 or fewer characters)'; Official = 'Official'; NoMatch = '(no match)'; OcrError = 'OCR error'; GameUnavailable = 'Game window unavailable. Start the game and use windowed or borderless mode.'
    }
    ZH = @{
        SettingsTitle = '字幕设置'; OcrTab = '识别'; SubtitleTab = '字幕'
        OcrLeft = '识别区域左侧 (%)'; OcrTop = '识别区域顶部 (%)'; OcrWidth = '识别区域宽度 (%)'; OcrHeight = '识别区域高度 (%)'
        PluginLanguage = '插件语言'; RecognitionLanguage = '识别语言'; SubtitleLanguage = '识别后字幕语言'
        Chinese = '中文'; English = '英文'; MaxFontSize = '最大字体大小'
        SubtitleLeft = '字幕左侧 (%)'; SubtitleTop = '字幕顶部 (%)'; SubtitleWidth = '字幕宽度 (%)'; SubtitleHeight = '字幕高度 (%)'; TextPadding = '文字边距 (px)'
        DragHint = '拖动蓝色选区内部可移动；拖动任意边或角可缩放；松开后自动保存位置和大小。'
        ShowOcrSelection = '显示可拖动的识别选区'; OcrIdle = 'OCR：点击“预览识别区域”检查实际截图'
        PreviewOcr = '预览识别区域'; Reset = '重置'; Close = '关闭'; Settings = '设置'; Exit = '退出'
        HideToolbar = '收起工具栏'; DragToolbar = '拖动以移动'; ShowToolbar = '展开工具栏；拖动以移动'
        DragSubtitle = '拖动字幕以调整位置'; PreviewInput = '预览：实际 OCR 输入'; PreviewError = '预览错误'
        OcrNoText = 'OCR：识别区域内没有文字'; OcrShort = 'OCR（不超过 10 个字符）'; Official = '官方'; NoMatch = '（未匹配）'; OcrError = 'OCR 错误'; GameUnavailable = '未检测到可用的游戏窗口。请先启动游戏，并使用窗口化或无边框模式。'
    }
}
function Get-UiText([string]$Name) { return [string]$uiStrings[$config.PluginLanguage][$Name] }
function Get-LanguageName([string]$Language) { if ($Language -eq 'EN') { return Get-UiText 'English' } return Get-UiText 'Chinese' }

$subtitle = New-Object GenshinSubtitleClickThroughForm
$subtitle.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$subtitle.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$subtitle.ShowInTaskbar = $false
$subtitle.TopMost = $true
$subtitle.BackColor = [Drawing.Color]::Magenta
$subtitle.TransparencyKey = [Drawing.Color]::Magenta
$subtitle.Opacity = 1.0
$label = New-Object System.Windows.Forms.Label
$label.Dock = [System.Windows.Forms.DockStyle]::Fill
$label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$label.ForeColor = [Drawing.Color]::White
$label.BackColor = [Drawing.Color]::Transparent
$label.Font = [Drawing.Font]::new('Microsoft YaHei UI', [single]$config.FontSize, [Drawing.FontStyle]::Bold)
$label.Padding = New-Object System.Windows.Forms.Padding($config.TextPadding)
$label.AutoEllipsis = $false
$subtitle.Controls.Add($label)
$selection = New-Object GenshinSubtitleSelectionForm

$cropFrame = New-Object GenshinSubtitleCropForm
$cropFrame.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$cropFrame.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$cropFrame.ShowInTaskbar = $false
$cropFrame.TopMost = $true

$toolbar = New-Object GenshinSubtitleToolbarForm
$toolbar.Text = 'Genshin Subtitle Overlay'
$toolbar.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$toolbar.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$toolbar.ShowInTaskbar = $false
$toolbar.TopMost = $true
$toolbar.BackColor = [Drawing.Color]::FromArgb(245, 245, 245)
$toolbar.Width = 360
$toolbar.Height = 42
$btnToggle = New-Object System.Windows.Forms.Button
$btnToggle.Location = New-Object Drawing.Point(24, 4)
$btnToggle.Size = New-Object Drawing.Size(68, 30)
$btnLang = New-Object System.Windows.Forms.Button
$btnLang.Location = New-Object Drawing.Point(98, 4)
$btnLang.Size = New-Object Drawing.Size(68, 30)
$btnSettings = New-Object System.Windows.Forms.Button
$btnSettings.Location = New-Object Drawing.Point(172, 4)
$btnSettings.Size = New-Object Drawing.Size(68, 30)
$btnExit = New-Object System.Windows.Forms.Button
$btnExit.Location = New-Object Drawing.Point(246, 4)
$btnExit.Size = New-Object Drawing.Size(68, 30)
[void]$toolbar.Controls.Add($btnToggle)
[void]$toolbar.Controls.Add($btnLang)
[void]$toolbar.Controls.Add($btnSettings)
[void]$toolbar.Controls.Add($btnExit)
$btnHide = New-Object System.Windows.Forms.Button
$btnHide.Location = [Drawing.Point]::new(320, 4)
$btnHide.Size = [Drawing.Size]::new(32, 30)
$btnHide.Font = [Drawing.Font]::new('Marlett', 12)
$btnHide.Text = '0'
[void]$toolbar.Controls.Add($btnHide)
$toolbarTips = New-Object System.Windows.Forms.ToolTip

function Save-ToolbarPosition {
    $bounds = $toolbar.MovementBounds
    Update-OverlayConfig @{ ToolbarLeft=[Math]::Round(($toolbar.Left - $bounds.Left) * 100.0 / [Math]::Max(1, $bounds.Width), 2); ToolbarTop=[Math]::Round(($toolbar.Top - $bounds.Top) * 100.0 / [Math]::Max(1, $bounds.Height), 2) }
}
function Set-ToolbarCollapsed([bool]$Collapsed, [bool]$Persist = $true) {
    Update-OverlayConfig @{ ToolbarCollapsed=$Collapsed } $false
    $toolbar.Collapsed = $Collapsed
    foreach ($button in @($btnToggle, $btnLang, $btnSettings, $btnExit, $btnHide)) { $button.Visible = !$Collapsed }
    $toolbar.Size = if ($Collapsed) { [Drawing.Size]::new(40, 40) } else { [Drawing.Size]::new(360, 42) }
    $toolbarTips.SetToolTip($toolbar, $(if ($Collapsed) { Get-UiText 'ShowToolbar' } else { Get-UiText 'DragToolbar' }))
    if ($state.LastBounds) { Update-Layout $state.LastBounds }
    $toolbar.Invalidate()
    if ($Persist) { Save-ToolbarPosition }
}
$btnHide.Add_Click({ Set-ToolbarCollapsed $true })
$toolbar.Add_RestoreRequested({ Set-ToolbarCollapsed $false })
$toolbar.Add_DragCompleted({ Save-ToolbarPosition })

function Update-Buttons {
    $btnToggle.Text = if ($config.PluginLanguage -eq 'ZH') { if ($state.Enabled) { '开' } else { '关' } } else { if ($state.Enabled) { 'ON' } else { 'OFF' } }
    $btnLang.Text = if ($state.Language -eq 'EN') { 'EN' } else { 'ZH' }
    $btnSettings.Text = Get-UiText 'Settings'
    $btnExit.Text = Get-UiText 'Exit'
}
function Get-SubtitleTextHeight([string]$Text, [int]$ContentWidth, [int]$ContentHeight) {
    if (!$Text) {
        if ($label.Font.Size -ne $config.FontSize) {
            $previousFont = $label.Font
            $label.Font = [Drawing.Font]::new('Microsoft YaHei UI', [single]$config.FontSize, [Drawing.FontStyle]::Bold)
            $previousFont.Dispose()
        }
        $state.LayoutKey = ''
        $state.MeasuredHeight = 0
        return 0
    }
    $key = $Text + '|' + $ContentWidth + '|' + $ContentHeight + '|' + $config.FontSize
    if ($state.LayoutKey -eq $key) { return [int]$state.MeasuredHeight }
    $flags = [System.Windows.Forms.TextFormatFlags]::WordBreak -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix -bor [System.Windows.Forms.TextFormatFlags]::NoPadding
    $selectedFont = $null
    $measured = $null
    for ($size = [int]$config.FontSize; $size -ge 8; $size--) {
        $candidate = [Drawing.Font]::new('Microsoft YaHei UI', [single]$size, [Drawing.FontStyle]::Bold)
        $candidateSize = [System.Windows.Forms.TextRenderer]::MeasureText($Text, $candidate, [Drawing.Size]::new($ContentWidth, 10000), $flags)
        if ($candidateSize.Height -le $ContentHeight -and $candidateSize.Width -le $ContentWidth) {
            $selectedFont = $candidate
            $measured = $candidateSize
            break
        }
        $candidate.Dispose()
    }
    if (!$selectedFont) {
        $selectedFont = [Drawing.Font]::new('Microsoft YaHei UI', [single]8, [Drawing.FontStyle]::Bold)
        $measured = [System.Windows.Forms.TextRenderer]::MeasureText($Text, $selectedFont, [Drawing.Size]::new($ContentWidth, 10000), $flags)
    }
    if ($label.Font.Size -ne $selectedFont.Size) {
        $previousFont = $label.Font
        $label.Font = $selectedFont
        $previousFont.Dispose()
    } else {
        $selectedFont.Dispose()
    }
    $state.LayoutKey = $key
    $state.MeasuredHeight = $measured.Height
    return [int]$measured.Height
}
function Update-Layout([object]$Bounds) {
    $left = [int](@($Bounds.Left)[0])
    $top = [int](@($Bounds.Top)[0])
    $right = [int](@($Bounds.Right)[0])
    $bottom = [int](@($Bounds.Bottom)[0])
    $width = $right - $left
    $height = $bottom - $top
    $crop = Get-CropRectangle $Bounds
    $cropFrame.MovementBounds = [Drawing.Rectangle]::FromLTRB($left, $top, $right, $bottom)
    if (!$cropFrame.IsDragging) { $cropFrame.Bounds = $crop }
    $cropFrame.Visible = [bool]($settingsForm.Visible -and $config.ShowFrame)
    $subtitleW = [Math]::Min($width, [Math]::Max(128, [int]($width * $config.DisplayWidth / 100)))
    $subtitleX = $left + [int]($width * $config.DisplayLeft / 100)
    $maxSubtitleH = [Math]::Min($height, [Math]::Max(64, [int]($height * $config.DisplayHeight / 100)))
    $contentWidth = [Math]::Max(20, $subtitleW - 2 * $config.TextPadding - 8)
    $contentHeight = [Math]::Max(20, $maxSubtitleH - 2 * $config.TextPadding - 8)
    $label.Padding = New-Object System.Windows.Forms.Padding($config.TextPadding)
    $measuredHeight = Get-SubtitleTextHeight $label.Text $contentWidth $contentHeight
    $subtitleH = $maxSubtitleH
    $subtitleY = $top + [int]($height * $config.DisplayTop / 100)
    $subtitleX = [Math]::Max($left, [Math]::Min($right - $subtitleW, $subtitleX))
    $subtitleY = [Math]::Max($top, [Math]::Min($bottom - $subtitleH, $subtitleY))
    $subtitle.Bounds = [Drawing.Rectangle]::new($subtitleX, $subtitleY, $subtitleW, $subtitleH)
    $selection.MovementBounds = [Drawing.Rectangle]::FromLTRB($left, $top, $right, $bottom)
    if (!$selection.IsDragging) { $selection.Bounds = $subtitle.Bounds }
    $toolbar.MovementBounds = [Drawing.Rectangle]::FromLTRB($left, $top, $right, $bottom)
    if (!$toolbar.IsDragging) {
        $toolbarX = if ($config.ToolbarLeft -ge 0) { $left + [int]($width * $config.ToolbarLeft / 100) } else { $right - $toolbar.Width - 18 }
        $toolbarY = if ($config.ToolbarTop -ge 0) { $top + [int]($height * $config.ToolbarTop / 100) } else { $bottom - $toolbar.Height - 70 }
        $toolbarX = [Math]::Max($left, [Math]::Min($right - $toolbar.Width, $toolbarX))
        $toolbarY = [Math]::Max($top, [Math]::Min($bottom - $toolbar.Height, $toolbarY))
        $toolbar.Location = [Drawing.Point]::new($toolbarX, $toolbarY)
    }
}
function Set-Subtitle([string]$Text) {
    if ($Text -and $state.Enabled) {
        $label.Text = $Text
        if ($state.LastBounds) { Update-Layout $state.LastBounds }
        $subtitle.Visible = $true
    } else {
        $label.Text = ''
        $subtitle.Visible = $false
    }
}
function Get-CurrentSubtitleText {
    if ($state.Language -eq $config.RecognitionLanguage) { return $state.LastSource }
    return $state.LastOpposite
}
function Set-SubtitleLanguage([string]$Language, [bool]$Persist = $true) {
    if ($Language -notin @('ZH', 'EN')) { return }
    $state.Language = $Language
    Update-OverlayConfig @{ SubtitleLanguage=$Language } $Persist
    if ($null -ne $settingSubtitleLanguage) {
        $script:settingsReady = $false
        try { $settingSubtitleLanguage.SelectedIndex = if ($Language -eq 'EN') { 1 } else { 0 } }
        finally { $script:settingsReady = $true }
    }
    Update-Buttons
    if ($state.LastSource -or $state.LastOpposite) { Set-Subtitle (Get-CurrentSubtitleText) }
}
function Switch-SubtitleLanguage {
    Set-SubtitleLanguage $(if ($state.Language -eq 'EN') { 'ZH' } else { 'EN' })
}

$settingsForm = New-Object System.Windows.Forms.Form
$settingsForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$settingsForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$settingsForm.ClientSize = [Drawing.Size]::new(500, 650)
$settingsForm.ShowInTaskbar = $false
$settingsForm.TopMost = $true
$settingsForm.MaximizeBox = $false
$settingsForm.MinimizeBox = $false
$settingsForm.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$settingsForm.Location = [Drawing.Point]::new([System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Left + 20, [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Top + 20)
$settingsTabs = New-Object System.Windows.Forms.TabControl
$settingsTabs.Location = [Drawing.Point]::new(8, 8)
$settingsTabs.Size = [Drawing.Size]::new(484, 590)
$ocrTab = New-Object System.Windows.Forms.TabPage
$displayTab = New-Object System.Windows.Forms.TabPage
[void]$settingsTabs.TabPages.Add($ocrTab)
[void]$settingsTabs.TabPages.Add($displayTab)
[void]$settingsForm.Controls.Add($settingsTabs)

function Add-NumberSetting([System.Windows.Forms.Control]$Parent, [string]$Caption, [double]$Value, [int]$Min, [double]$Max, [int]$RowY, [bool]$Decimal = $false) {
    $captionLabel = New-Object System.Windows.Forms.Label
    $captionLabel.Text = $Caption
    $captionLabel.Location = [Drawing.Point]::new(18, $RowY + 4)
    $captionLabel.Size = [Drawing.Size]::new(245, 24)
    [void]$Parent.Controls.Add($captionLabel)
    $input = New-Object System.Windows.Forms.NumericUpDown
    $input.Minimum = $Min
    $input.Maximum = $Max
    if ($Decimal) { $input.DecimalPlaces = 2; $input.Increment = 0.1 }
    $input.Value = $Value
    $input.Location = [Drawing.Point]::new(370, $RowY)
    $input.Size = [Drawing.Size]::new(85, 26)
    $input.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Right
    $input.Tag = $captionLabel
    [void]$Parent.Controls.Add($input)
    return $input
}
function Add-LanguageSetting([System.Windows.Forms.Control]$Parent, [string]$Caption, [string]$Value, [int]$RowY) {
    $captionLabel = New-Object System.Windows.Forms.Label
    $captionLabel.Text = $Caption
    $captionLabel.Location = [Drawing.Point]::new(18, $RowY + 4)
    $captionLabel.Size = [Drawing.Size]::new(300, 24)
    [void]$Parent.Controls.Add($captionLabel)
    $input = New-Object System.Windows.Forms.ComboBox
    $input.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $input.Location = [Drawing.Point]::new(330, $RowY)
    $input.Size = [Drawing.Size]::new(125, 26)
    [void]$input.Items.AddRange(@((Get-UiText 'Chinese'), (Get-UiText 'English')))
    $input.SelectedIndex = if ($Value -eq 'EN') { 1 } else { 0 }
    $input.Tag = $captionLabel
    [void]$Parent.Controls.Add($input)
    return $input
}

$settingLeft = Add-NumberSetting $ocrTab (Get-UiText 'OcrLeft') $config.Left 0 95 16 $true
$settingTop = Add-NumberSetting $ocrTab (Get-UiText 'OcrTop') $config.Top 0 95 51 $true
$settingWidth = Add-NumberSetting $ocrTab (Get-UiText 'OcrWidth') $config.Width 5 (100 - $config.Left) 86 $true
$settingHeight = Add-NumberSetting $ocrTab (Get-UiText 'OcrHeight') $config.Height 5 (100 - $config.Top) 121 $true
$settingPluginLanguage = Add-LanguageSetting $ocrTab (Get-UiText 'PluginLanguage') $config.PluginLanguage 156
$settingRecognitionLanguage = Add-LanguageSetting $ocrTab (Get-UiText 'RecognitionLanguage') $config.RecognitionLanguage 191
$settingSubtitleLanguage = Add-LanguageSetting $ocrTab (Get-UiText 'SubtitleLanguage') $config.SubtitleLanguage 226
$settingFont = Add-NumberSetting $displayTab (Get-UiText 'MaxFontSize') $config.FontSize 12 48 20
$settingDisplayLeft = Add-NumberSetting $displayTab (Get-UiText 'SubtitleLeft') $config.DisplayLeft 0 95 65 $true
$settingDisplayTop = Add-NumberSetting $displayTab (Get-UiText 'SubtitleTop') $config.DisplayTop 0 95 110 $true
$settingDisplayWidth = Add-NumberSetting $displayTab (Get-UiText 'SubtitleWidth') $config.DisplayWidth 5 (100 - $config.DisplayLeft) 155 $true
$settingDisplayHeight = Add-NumberSetting $displayTab (Get-UiText 'SubtitleHeight') $config.DisplayHeight 5 100 200 $true
$settingTextPadding = Add-NumberSetting $displayTab (Get-UiText 'TextPadding') $config.TextPadding 0 40 245
$dragHint = New-Object System.Windows.Forms.Label
$dragHint.Location = [Drawing.Point]::new(18, 300)
$dragHint.Size = [Drawing.Size]::new(430, 80)
[void]$displayTab.Controls.Add($dragHint)
$settingFrame = New-Object System.Windows.Forms.CheckBox
$settingFrame.Checked = $config.ShowFrame
$settingFrame.Location = [Drawing.Point]::new(18, 264)
$settingFrame.Size = [Drawing.Size]::new(445, 25)
[void]$ocrTab.Controls.Add($settingFrame)
$ocrStatus = New-Object System.Windows.Forms.TextBox
$ocrStatus.ReadOnly = $true
$ocrStatus.Multiline = $true
$ocrStatus.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$ocrStatus.Location = [Drawing.Point]::new(18, 296)
$ocrStatus.Size = [Drawing.Size]::new(445, 72)
[void]$ocrTab.Controls.Add($ocrStatus)
$previewButton = New-Object System.Windows.Forms.Button
$previewButton.Location = [Drawing.Point]::new(18, 376)
$previewButton.Size = [Drawing.Size]::new(220, 30)
[void]$ocrTab.Controls.Add($previewButton)
$previewImage = New-Object System.Windows.Forms.PictureBox
$previewImage.Location = [Drawing.Point]::new(18, 414)
$previewImage.Size = [Drawing.Size]::new(445, 145)
$previewImage.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$previewImage.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
[void]$ocrTab.Controls.Add($previewImage)
$resetSettings = New-Object System.Windows.Forms.Button
$resetSettings.Location = [Drawing.Point]::new(310, 610)
$resetSettings.Size = [Drawing.Size]::new(82, 30)
[void]$settingsForm.Controls.Add($resetSettings)
$closeSettings = New-Object System.Windows.Forms.Button
$closeSettings.Location = [Drawing.Point]::new(402, 610)
$closeSettings.Size = [Drawing.Size]::new(82, 30)
[void]$settingsForm.Controls.Add($closeSettings)

function Set-ComboLanguageItems([System.Windows.Forms.ComboBox]$Combo) {
    $selected = $Combo.SelectedIndex
    $Combo.Items.Clear()
    [void]$Combo.Items.AddRange(@((Get-UiText 'Chinese'), (Get-UiText 'English')))
    $Combo.SelectedIndex = $selected
}
function Apply-UiLanguage {
    $settingsForm.Text = Get-UiText 'SettingsTitle'
    $ocrTab.Text = Get-UiText 'OcrTab'; $displayTab.Text = Get-UiText 'SubtitleTab'
    $settingLeft.Tag.Text = Get-UiText 'OcrLeft'; $settingTop.Tag.Text = Get-UiText 'OcrTop'
    $settingWidth.Tag.Text = Get-UiText 'OcrWidth'; $settingHeight.Tag.Text = Get-UiText 'OcrHeight'
    $settingPluginLanguage.Tag.Text = Get-UiText 'PluginLanguage'
    $settingRecognitionLanguage.Tag.Text = Get-UiText 'RecognitionLanguage'
    $settingSubtitleLanguage.Tag.Text = Get-UiText 'SubtitleLanguage'
    $settingFont.Tag.Text = Get-UiText 'MaxFontSize'; $settingDisplayLeft.Tag.Text = Get-UiText 'SubtitleLeft'
    $settingDisplayTop.Tag.Text = Get-UiText 'SubtitleTop'; $settingDisplayWidth.Tag.Text = Get-UiText 'SubtitleWidth'
    $settingDisplayHeight.Tag.Text = Get-UiText 'SubtitleHeight'; $settingTextPadding.Tag.Text = Get-UiText 'TextPadding'
    $script:settingsReady = $false
    try {
        Set-ComboLanguageItems $settingPluginLanguage
        Set-ComboLanguageItems $settingRecognitionLanguage
        Set-ComboLanguageItems $settingSubtitleLanguage
    } finally { $script:settingsReady = $true }
    $dragHint.Text = Get-UiText 'DragHint'; $settingFrame.Text = Get-UiText 'ShowOcrSelection'
    if (!$state.LastOcr) { $ocrStatus.Text = Get-UiText 'OcrIdle' }
    $previewButton.Text = Get-UiText 'PreviewOcr'; $resetSettings.Text = Get-UiText 'Reset'; $closeSettings.Text = Get-UiText 'Close'
    $toolbarTips.SetToolTip($btnHide, (Get-UiText 'HideToolbar'))
    $toolbarTips.SetToolTip($toolbar, $(if ($toolbar.Collapsed) { Get-UiText 'ShowToolbar' } else { Get-UiText 'DragToolbar' }))
    Update-Buttons
}

$script:settingsReady = $true
Apply-UiLanguage
function Apply-Settings {
    if (!$script:settingsReady) { return }
    $script:settingsReady = $false
    $settingWidth.Maximum = 100 - $settingLeft.Value
    $settingHeight.Maximum = 100 - $settingTop.Value
    $settingDisplayWidth.Maximum = 100 - $settingDisplayLeft.Value
    $script:settingsReady = $true
    $previousUi = $config.PluginLanguage
    Update-OverlayConfig @{
        Left=[double]$settingLeft.Value; Top=[double]$settingTop.Value; Width=[double]$settingWidth.Value; Height=[double]$settingHeight.Value
        FontSize=[int]$settingFont.Value; ShowFrame=$settingFrame.Checked
        PluginLanguage=$(if ($settingPluginLanguage.SelectedIndex -eq 1) {'EN'} else {'ZH'})
        RecognitionLanguage=$(if ($settingRecognitionLanguage.SelectedIndex -eq 1) {'EN'} else {'ZH'})
        SubtitleLanguage=$(if ($settingSubtitleLanguage.SelectedIndex -eq 1) {'EN'} else {'ZH'})
        DisplayLeft=[double]$settingDisplayLeft.Value; DisplayTop=[double]$settingDisplayTop.Value
        DisplayWidth=[double]$settingDisplayWidth.Value; DisplayHeight=[double]$settingDisplayHeight.Value; TextPadding=[int]$settingTextPadding.Value
    }
    if ($previousUi -ne $config.PluginLanguage) { Apply-UiLanguage }
    if ($state.Language -ne $config.SubtitleLanguage) { Set-SubtitleLanguage $config.SubtitleLanguage $false }
    if ($state.LastBounds) { Update-Layout $state.LastBounds }
}
foreach ($input in @($settingLeft, $settingTop, $settingWidth, $settingHeight, $settingFont, $settingDisplayLeft, $settingDisplayTop, $settingDisplayWidth, $settingDisplayHeight, $settingTextPadding)) {
    $input.Add_ValueChanged({ Apply-Settings })
}
$settingFrame.Add_CheckedChanged({ Apply-Settings })
$settingPluginLanguage.Add_SelectedIndexChanged({ Apply-Settings })
$settingRecognitionLanguage.Add_SelectedIndexChanged({ Apply-Settings })
$settingSubtitleLanguage.Add_SelectedIndexChanged({ Apply-Settings })
$resetSettings.Add_Click({
    $script:settingsReady = $false
    $settingLeft.Value = 16.5; $settingTop.Value = 84
    $settingWidth.Maximum = 100; $settingHeight.Maximum = 100; $settingDisplayWidth.Maximum = 100
    $settingWidth.Value = 67; $settingHeight.Value = 9.5
    $settingFont.Value = 24; $settingFrame.Checked = $true
    $settingPluginLanguage.SelectedIndex = 0
    $settingRecognitionLanguage.SelectedIndex = 1
    $settingSubtitleLanguage.SelectedIndex = 1
    $settingDisplayLeft.Value = 16.5; $settingDisplayTop.Value = 93.5; $settingDisplayWidth.Value = 67
    $settingDisplayHeight.Value = 5.5; $settingTextPadding.Value = 16
    $script:settingsReady = $true
    Apply-Settings
})
$closeSettings.Add_Click({ $settingsForm.Hide() })
$settingsForm.Add_FormClosing({ param($sender, $eventArgs) $eventArgs.Cancel = $true; $settingsForm.Hide() })

function Sync-SubtitleSelection([bool]$Persist = $false) {
    if (!$state.LastBounds) { return }
    $bounds = $state.LastBounds
    $gameLeft = [int](@($bounds.Left)[0]); $gameTop = [int](@($bounds.Top)[0])
    $gameWidth = [Math]::Max(1, [int](@($bounds.Right)[0]) - $gameLeft)
    $gameHeight = [Math]::Max(1, [int](@($bounds.Bottom)[0]) - $gameTop)
    $displayLeft = [Math]::Round((($selection.Left - $gameLeft) * 100.0) / $gameWidth, 2)
    $displayTop = [Math]::Round((($selection.Top - $gameTop) * 100.0) / $gameHeight, 2)
    $config.DisplayLeft = [Math]::Max(0.0, [Math]::Min(95.0, $displayLeft))
    $config.DisplayTop = [Math]::Max(0.0, [Math]::Min(95.0, $displayTop))
    $config.DisplayWidth = [Math]::Max(5.0, [Math]::Min(100.0 - $config.DisplayLeft, [Math]::Round($selection.Width * 100.0 / $gameWidth, 2)))
    $config.DisplayHeight = [Math]::Max(5.0, [Math]::Min(100.0, [Math]::Round($selection.Height * 100.0 / $gameHeight, 2)))
    $script:settingsReady = $false
    try {
        $settingDisplayLeft.Value = $config.DisplayLeft
        $settingDisplayTop.Value = $config.DisplayTop
        $settingDisplayWidth.Maximum = 100 - $settingDisplayLeft.Value
        $settingDisplayWidth.Value = $config.DisplayWidth
        $settingDisplayHeight.Value = $config.DisplayHeight
    }
    finally { $script:settingsReady = $true }
    Update-OverlayConfig @{} $Persist
    Update-Layout $state.LastBounds
}

function Sync-CropSelection([bool]$Persist = $false) {
    if (!$state.LastBounds) { return }
    $bounds = $state.LastBounds
    $gameLeft = [int](@($bounds.Left)[0]); $gameTop = [int](@($bounds.Top)[0])
    $gameWidth = [Math]::Max(1, [int](@($bounds.Right)[0]) - $gameLeft)
    $gameHeight = [Math]::Max(1, [int](@($bounds.Bottom)[0]) - $gameTop)
    $displayLeft = [Math]::Round((($cropFrame.Left - $gameLeft) * 100.0) / $gameWidth, 2)
    $displayTop = [Math]::Round((($cropFrame.Top - $gameTop) * 100.0) / $gameHeight, 2)
    $config.Left = [Math]::Max(0.0, [Math]::Min(95.0, $displayLeft))
    $config.Top = [Math]::Max(0.0, [Math]::Min(95.0, $displayTop))
    $config.Width = [Math]::Max(5.0, [Math]::Min(100.0 - $config.Left, [Math]::Round($cropFrame.Width * 100.0 / $gameWidth, 2)))
    $config.Height = [Math]::Max(5.0, [Math]::Min(100.0 - $config.Top, [Math]::Round($cropFrame.Height * 100.0 / $gameHeight, 2)))
    Reset-ScanState
    $script:settingsReady = $false
    try {
        $settingLeft.Value = $config.Left
        $settingTop.Value = $config.Top
        $settingWidth.Maximum = 100 - $settingLeft.Value
        $settingWidth.Value = $config.Width
        $settingHeight.Maximum = 100 - $settingTop.Value
        $settingHeight.Value = $config.Height
    }
    finally { $script:settingsReady = $true }
    Update-OverlayConfig @{} $Persist
    Update-Layout $state.LastBounds
}

$cropFrame.Add_BoundsEdited({ if ($settingsForm.Visible) { Sync-CropSelection } })
$cropFrame.Add_EditCompleted({ if ($settingsForm.Visible) { Sync-CropSelection $true } })
$selection.Add_BoundsEdited({ if ($settingsForm.Visible) { Sync-SubtitleSelection } })
$selection.Add_EditCompleted({ if ($settingsForm.Visible) { Sync-SubtitleSelection $true } })
$settingsForm.Add_VisibleChanged({
    if ($settingsForm.Visible) {
        Reset-ScanState
        if (!$subtitle.Visible) {
            $state.SettingsPreview = $true
            $state.SettingsPreviousText = $label.Text
            $state.SettingsPreviousVisible = $subtitle.Visible
            $label.Text = Get-UiText 'DragSubtitle'
            if ($state.LastBounds) { Update-Layout $state.LastBounds }
            $subtitle.Visible = $true
        } elseif ($state.LastBounds) {
            Update-Layout $state.LastBounds
        }
        $selection.Show()
        $selection.BringToFront()
        $settingsForm.BringToFront()
    } else {
        $selection.Hide()
        $cropFrame.Visible = $false
        if ($state.SettingsPreview) {
            $label.Text = $state.SettingsPreviousText
            $subtitle.Visible = [bool]$state.SettingsPreviousVisible
            $state.SettingsPreview = $false
        }
    }
})
$previewButton.Add_Click({
    try {
        $bounds = Get-GameBounds
        if (!$bounds) { throw (Get-UiText 'GameUnavailable') }
        Update-Layout $bounds
        $settingsForm.Hide()
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 150
        Capture-SubtitleRegion (Get-CropFrameScreenBounds) $tempImage
        $loaded = [Drawing.Image]::FromFile($tempImage)
        try { $snapshot = [Drawing.Bitmap]::new($loaded) } finally { $loaded.Dispose() }
        $oldImage = $previewImage.Image
        $previewImage.Image = $snapshot
        if ($oldImage) { $oldImage.Dispose() }
        $ocrStatus.Text = (Get-UiText 'PreviewInput') + ' (' + $snapshot.Width + ' x ' + $snapshot.Height + ' px)'
    }
    catch { $ocrStatus.Text = (Get-UiText 'PreviewError') + ': ' + $_.Exception.Message }
    finally { $settingsForm.Show(); $settingsForm.Activate() }
})

$btnToggle.Add_Click({ Set-OverlayEnabled (!$state.Enabled) })
$btnLang.Add_Click({ Switch-SubtitleLanguage })
$btnSettings.Add_Click({ $settingsForm.Show(); $settingsForm.BringToFront(); $settingsForm.Activate() })
$btnExit.Add_Click({ $toolbar.Close() })
$toolbar.Add_FormClosed({ Stop-ScanWorker; $selection.Dispose(); [System.Windows.Forms.Application]::ExitThread() })

$subtitle.Add_Shown({ [GenshinSubtitleOverlayNative]::MakeNoActivate($subtitle.Handle) })
$toolbar.Add_Shown({ Update-Buttons })
$subtitle.Visible = $false
$initialBounds = if ($UiCheck) { $null } else { Get-GameBounds }
if (!$initialBounds) {
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $initialBounds = New-Object GenshinSubtitleOverlayNative+RECT
    $initialBounds.Left = $screen.Left; $initialBounds.Top = $screen.Top
    $initialBounds.Right = $screen.Right; $initialBounds.Bottom = $screen.Bottom
    $state.GameUnavailable = $true
}
$state.LastBounds = $initialBounds
Set-ToolbarCollapsed ([bool]$config.ToolbarCollapsed) $false
Update-Layout $initialBounds
Update-Buttons
$toolbar.Show()
if ($configLoadError) { $ocrStatus.Text = 'Settings could not be read and were left untouched: ' + $configLoadError }
elseif ($state.GameUnavailable) { $ocrStatus.Text = Get-UiText 'GameUnavailable' }
[GenshinSubtitleOverlayNative]::MakeNoActivate($subtitle.Handle)
