$settingsPath = Join-Path $root 'data/overlay-settings.json'
$settingsExistedAtStartup = Test-Path -LiteralPath $settingsPath
$config = @{
    Left = 16.5; Top = 84; Width = 67; Height = 9.5
    FontSize = 24; ShowFrame = $true
    DisplayLeft = 16.5; DisplayTop = 93.5; DisplayWidth = 67; DisplayHeight = 5.5
    DisplayGap = 12; TextPadding = 16
    PluginLanguage = 'ZH'; RecognitionLanguage = 'EN'; SubtitleLanguage = 'EN'
}
$hasSavedDisplayTop = $true
$config.ToolbarLeft = -1.0; $config.ToolbarTop = -1.0; $config.ToolbarCollapsed = $false
if ($settingsExistedAtStartup) {
    try {
        $saved = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($name in @('Left', 'Top', 'Width', 'Height', 'FontSize', 'DisplayLeft', 'DisplayTop', 'DisplayWidth', 'DisplayHeight', 'DisplayGap', 'TextPadding', 'ToolbarLeft', 'ToolbarTop')) {
            if ($null -ne $saved.$name) { $config[$name] = [double]$saved.$name }
        }
        $hasSavedDisplayTop = $null -ne $saved.DisplayTop
        if ($null -ne $saved.ShowFrame) { $config.ShowFrame = [bool]$saved.ShowFrame }
        if ($null -ne $saved.ToolbarCollapsed) { $config.ToolbarCollapsed = [bool]$saved.ToolbarCollapsed }
        if ($saved.PluginLanguage -in @('ZH', 'EN')) { $config.PluginLanguage = [string]$saved.PluginLanguage }
        if ($saved.RecognitionLanguage -in @('ZH', 'EN')) {
            $config.RecognitionLanguage = [string]$saved.RecognitionLanguage
        } elseif ($saved.SourceLanguage -in @('ZH', 'EN')) {
            # Preserve the input direction chosen by older versions.
            $config.RecognitionLanguage = [string]$saved.SourceLanguage
        }
        if ($saved.SubtitleLanguage -in @('ZH', 'EN')) { $config.SubtitleLanguage = [string]$saved.SubtitleLanguage }
    } catch {
        Add-Content -LiteralPath (Join-Path $root 'overlay-errors.log') -Value ((Get-Date -Format o) + ' Invalid settings: ' + $_.Exception.Message)
    }
}
$config.Left = [Math]::Max(0.0, [Math]::Min(95.0, [double]$config.Left))
$config.Top = [Math]::Max(0.0, [Math]::Min(95.0, [double]$config.Top))
$config.Width = [Math]::Max(5.0, [Math]::Min(100.0, [double]$config.Width))
$config.Height = [Math]::Max(5.0, [Math]::Min(100.0, [double]$config.Height))
$config.Width = [Math]::Min([double]$config.Width, 100.0 - $config.Left)
$config.Height = [Math]::Min([double]$config.Height, 100.0 - $config.Top)
$config.FontSize = [Math]::Max(12, [Math]::Min(48, $config.FontSize))
$config.DisplayLeft = [Math]::Max(0.0, [Math]::Min(95.0, $config.DisplayLeft))
$config.DisplayTop = if ($hasSavedDisplayTop) {
    [Math]::Max(0.0, [Math]::Min(95.0, $config.DisplayTop))
} else {
    [Math]::Max(0, [Math]::Min(95, $config.Top - $config.DisplayHeight - 2))
}
$config.DisplayWidth = [Math]::Max(5.0, [Math]::Min(100.0 - $config.DisplayLeft, $config.DisplayWidth))
$config.DisplayHeight = [Math]::Max(5.0, [Math]::Min(100.0, $config.DisplayHeight))
$config.DisplayGap = [Math]::Max(0, [Math]::Min(200, $config.DisplayGap))
$config.TextPadding = [Math]::Max(0, [Math]::Min(40, $config.TextPadding))
$freshDefaultsApplied = !$settingsExistedAtStartup -and $config.Left -eq 16.5 -and $config.Top -eq 84 -and $config.Width -eq 67 -and $config.Height -eq 9.5 -and
    $config.FontSize -eq 24 -and $config.DisplayLeft -eq 16.5 -and $config.DisplayTop -eq 93.5 -and $config.DisplayWidth -eq 67 -and
    $config.DisplayHeight -eq 5.5 -and $config.TextPadding -eq 16 -and $config.PluginLanguage -eq 'ZH' -and
    $config.RecognitionLanguage -eq 'EN' -and $config.SubtitleLanguage -eq 'EN'

function Save-OverlaySettings {
    $savePath = if ($UiCheck) { Join-Path $root 'test-results/overlay-ui-settings.json' } else { $settingsPath }
    $config | ConvertTo-Json | Set-Content -LiteralPath $savePath -Encoding UTF8
}
