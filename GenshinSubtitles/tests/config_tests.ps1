$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'modules/config.ps1')
$folder = Join-Path $root ('test-results/config-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $folder | Out-Null
try {
    $path = Join-Path $folder 'settings.json'
    $fresh = Read-OverlayConfig $path
    if ($fresh.Values.Left -ne 16.5 -or $fresh.Values.SubtitleLanguage -ne 'EN') { throw 'Fresh defaults changed.' }
    [IO.File]::WriteAllText($path, '{"SourceLanguage":"ZH","Left":"bad","Top":999,"Width":-1,"FontSize":"NaN","TextPadding":999,"ShowFrame":"false","ToolbarCollapsed":true}')
    $legacy = Read-OverlayConfig $path
    if ($legacy.Values.RecognitionLanguage -ne 'ZH' -or $legacy.Values.Left -ne 16.5 -or $legacy.Values.Top -ne 95 -or
        $legacy.Values.Width -ne 5 -or $legacy.Values.FontSize -ne 24 -or $legacy.Values.TextPadding -ne 40 -or
        !$legacy.Values.ShowFrame -or !$legacy.Values.ToolbarCollapsed) { throw 'Config migration or validation failed.' }
    Write-OverlayConfig $path $legacy.Values
    $loaded = Read-OverlayConfig $path
    if ($loaded.Values.RecognitionLanguage -ne 'ZH') { throw 'Atomic round-trip failed.' }
    if (!(Test-Path -LiteralPath ($path + '.bak'))) { throw 'Previous settings backup is missing.' }
    foreach ($bad in @('{broken', 'null', '[]', '42')) {
        [IO.File]::WriteAllText($path, $bad)
        $before = (Get-FileHash -LiteralPath $path).Hash
        $corrupt = Read-OverlayConfig $path
        if ($corrupt.Writable -or !$corrupt.Error -or $corrupt.Values.Left -ne 16.5) { throw 'Corrupt configuration accepted.' }
        $settingsPath=$path; $settingsWritable=$corrupt.Writable; $configLoadError=$corrupt.Error; $config=$corrupt.Values
        Save-OverlaySettings
        if ((Get-FileHash -LiteralPath $path).Hash -ne $before) { throw 'Unreadable personal settings were overwritten.' }
    }
    $blocked = Join-Path $folder 'blocked.json'
    Write-OverlayConfig $blocked (New-OverlayConfig)
    $before = (Get-FileHash -LiteralPath $blocked).Hash
    $lock = [IO.File]::Open($blocked,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    $failed=$false
    try { Write-OverlayConfig $blocked (New-OverlayConfig) } catch { $failed=$true } finally { $lock.Dispose() }
    if (!$failed -or (Get-FileHash -LiteralPath $blocked).Hash -ne $before) { throw 'Failed atomic write damaged the original.' }
    if (Get-ChildItem $folder -Filter '*.tmp') { throw 'Temporary configuration file leaked.' }
    Write-Output 'Configuration defaults, migration, invalid values, corrupt file preservation and atomic failure: OK'
} finally { Remove-Item -LiteralPath $folder -Recurse -Force }
