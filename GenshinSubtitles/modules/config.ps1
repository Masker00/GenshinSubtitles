# Persistent preferences only. Runtime state lives in runtime.ps1.
function New-OverlayConfig {
    return @{
        Left=16.5; Top=84.0; Width=67.0; Height=9.5; FontSize=24; ShowFrame=$true
        DisplayLeft=16.5; DisplayTop=93.5; DisplayWidth=67.0; DisplayHeight=5.5
        DisplayGap=12; TextPadding=16; PluginLanguage='ZH'; RecognitionLanguage='EN'; SubtitleLanguage='EN'
        ToolbarLeft=-1.0; ToolbarTop=-1.0; ToolbarCollapsed=$false
    }
}
function Repair-OverlayConfig([hashtable]$Values) {
    $defaults = New-OverlayConfig
    $ranges = @{
        Left=@(0.0,95.0); Top=@(0.0,95.0); Width=@(5.0,100.0); Height=@(5.0,100.0)
        DisplayLeft=@(0.0,95.0); DisplayTop=@(0.0,95.0); DisplayWidth=@(5.0,100.0); DisplayHeight=@(5.0,100.0)
        FontSize=@(12.0,48.0); DisplayGap=@(0.0,200.0); TextPadding=@(0.0,40.0)
        ToolbarLeft=@(-1.0,100.0); ToolbarTop=@(-1.0,100.0)
    }
    foreach ($key in $ranges.Keys) {
        $number = 0.0
        $valid = $null -ne $Values[$key] -and $Values[$key] -isnot [bool] -and
            [double]::TryParse([string]$Values[$key], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)
        if (!$valid -or [double]::IsNaN($number) -or [double]::IsInfinity($number)) { $number = $defaults[$key] }
        $Values[$key] = [Math]::Max([double]$ranges[$key][0], [Math]::Min([double]$ranges[$key][1], $number))
    }
    $Values.Width = [Math]::Min([double]$Values.Width, 100.0 - $Values.Left)
    $Values.Height = [Math]::Min([double]$Values.Height, 100.0 - $Values.Top)
    $Values.DisplayWidth = [Math]::Min([double]$Values.DisplayWidth, 100.0 - $Values.DisplayLeft)
    foreach ($key in @('FontSize','TextPadding','DisplayGap')) { $Values[$key] = [int]$Values[$key] }
    foreach ($key in @('ShowFrame','ToolbarCollapsed')) {
        if ($Values[$key] -isnot [bool]) { $Values[$key] = $defaults[$key] }
    }
    foreach ($key in @('PluginLanguage','RecognitionLanguage','SubtitleLanguage')) {
        if ($Values[$key] -notin @('ZH','EN')) { $Values[$key] = $defaults[$key] }
    }
}
function Read-OverlayConfig([string]$Path) {
    $values = New-OverlayConfig
    $problem = ''
    if (Test-Path -LiteralPath $Path) {
        try {
            $saved = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -eq $saved -or $saved.GetType().FullName -ne 'System.Management.Automation.PSCustomObject') { throw 'Settings must be a JSON object.' }
            foreach ($name in @($values.Keys)) {
                if ($null -ne $saved.$name) { $values[$name] = $saved.$name }
            }
            if ($saved.RecognitionLanguage -notin @('ZH','EN') -and $saved.SourceLanguage -in @('ZH','EN')) {
                $values.RecognitionLanguage = [string]$saved.SourceLanguage
            }
            Repair-OverlayConfig $values
            if ($null -eq $saved.DisplayTop) { $values.DisplayTop = [Math]::Max(0.0, [Math]::Min(95.0, $values.Top - $values.DisplayHeight - 2.0)) }
        } catch {
            $values = New-OverlayConfig
            $problem = 'Unreadable settings preserved at ' + $Path + '. Rename or repair that file before saving. ' + $_.Exception.Message
        }
    }
    return @{ Values=$values; Error=$problem; Writable=(!$problem) }
}
function Write-OverlayConfig([string]$Path, [hashtable]$Values) {
    Repair-OverlayConfig $Values
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $temporary = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, ($Values | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary, $Path, $Path + '.bak') }
        else { [IO.File]::Move($temporary, $Path) }
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
}
function Save-OverlaySettings {
    if (!$settingsWritable) {
        if ($ocrStatus) { $ocrStatus.Text = $configLoadError }
        return
    }
    try { Write-OverlayConfig $settingsPath $config }
    catch { if ($ocrStatus) { $ocrStatus.Text = 'Settings save failed: ' + $_.Exception.Message }; Write-Warning $_.Exception.Message }
}
function Update-OverlayConfig([hashtable]$Changes, [bool]$Persist=$true) {
    $before = @($config.RecognitionLanguage,$config.Left,$config.Top,$config.Width,$config.Height) -join '|'
    foreach ($name in $Changes.Keys) { if ($config.ContainsKey($name)) { $config[$name] = $Changes[$name] } }
    Repair-OverlayConfig $config
    $after = @($config.RecognitionLanguage,$config.Left,$config.Top,$config.Width,$config.Height) -join '|'
    if ($before -ne $after -and (Get-Command Reset-ScanState -ErrorAction SilentlyContinue)) { Reset-ScanState }
    if ($Persist) { Save-OverlaySettings }
}
function Initialize-OverlayConfig {
    $script:settingsPath = Join-Path $root 'data/overlay-settings.json'
    if ($UiCheck) { $script:settingsPath = Join-Path $root ('test-results/ui-config-' + [Guid]::NewGuid().ToString('N') + '/overlay-settings.json') }
    $script:settingsExistedAtStartup = Test-Path -LiteralPath $settingsPath
    $loaded = Read-OverlayConfig $settingsPath
    $script:config = $loaded.Values; $script:settingsWritable = $loaded.Writable; $script:configLoadError = $loaded.Error
    $script:freshDefaultsApplied = !$settingsExistedAtStartup
}
