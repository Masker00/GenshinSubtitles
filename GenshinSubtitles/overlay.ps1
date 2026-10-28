param(
    [switch]$CheckOnly,
    [switch]$UiCheck,
    [string]$ConfigDirectory
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $PSScriptRoot 'resolve-python.ps1')
$python = Resolve-SubtitlePython
$lookup = 'tools/lookup_ocr_text.py'
$db = 'data/subtitles-ocr.sqlite'
if (!(Test-Path -LiteralPath ($root + '/' + $db))) {
    throw 'OCR index is missing. Run prepare-ocr-index.ps1 first.'
}


. (Join-Path $root 'modules/platform.ps1')
. (Join-Path $root 'modules/config.ps1')
Initialize-OverlayConfig
. (Join-Path $root 'modules/capture.ps1')
. (Join-Path $root 'modules/query.ps1')
$ocrType = [Windows.Media.Ocr.OcrEngine,Windows.Media.Ocr,ContentType=WindowsRuntime]
$zhLanguage = [Windows.Globalization.Language,Windows.Globalization,ContentType=WindowsRuntime]::new('zh-Hans-CN')
$enLanguage = [Windows.Globalization.Language,Windows.Globalization,ContentType=WindowsRuntime]::new('en-US')
$zhEngine = $ocrType::TryCreateFromLanguage($zhLanguage)
$enEngine = $ocrType::TryCreateFromLanguage($enLanguage)
if (!$zhEngine -and !$enEngine) { throw 'Neither Chinese nor English Windows OCR is available.' }
if ($CheckOnly) {
    $testForm = New-Object GenshinSubtitleClickThroughForm
    $testForm.Dispose()
    [pscustomobject]@{ ocr = 'available'; chinese = [bool]$zhEngine; english = [bool]$enEngine; english_fallback = (!$enEngine -and [bool]$zhEngine); form = 'available' } | ConvertTo-Json
    exit 0
}
$tempImage = Join-Path ([IO.Path]::GetTempPath()) ('genshin-preview-' + [Guid]::NewGuid().ToString('N') + '.png')
$state = @{ Enabled = $true; Language = $config.SubtitleLanguage; Busy = $false; LastOcr = ''; LastLookup = ''; LastSource = ''; LastOpposite = ''; LastBounds = $null; Misses = 0; LayoutKey = ''; MeasuredHeight = 0; SettingsPreview = $false; SettingsPreviousText = ''; SettingsPreviousVisible = $false }


try {
    . (Join-Path $root 'modules/runtime.ps1')
    . (Join-Path $root 'modules/ui.ps1')
    if ($configLoadError -and !$UiCheck) { [void][Windows.Forms.MessageBox]::Show($configLoadError, 'Settings preserved') }
    if ($UiCheck) {
        New-Item -ItemType Directory -Force (Join-Path $root 'test-results') | Out-Null
        . (Join-Path $root 'tests/ui-check.ps1')
    } else { Start-OverlayRuntime }
} finally {
    Stop-ScanWorker
    if ($previewImage -and $previewImage.Image) { $previewImage.Image.Dispose() }
    foreach ($form in @($settingsForm,$cropFrame,$selection,$subtitle,$toolbar,$toolbarTips)) { if ($form) { $form.Dispose() } }
    if (Test-Path -LiteralPath $tempImage) { Remove-Item -LiteralPath $tempImage -Force -ErrorAction SilentlyContinue }
}
