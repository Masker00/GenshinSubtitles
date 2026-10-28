param([switch]$RunTests)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'resolve-python.ps1')
$python = Resolve-SubtitlePython
Write-Output "Python: $python"
& $python --version
foreach ($file in @('overlay.ps1', 'tools/lookup_ocr_text.py', 'tools/build_ocr_index.py', 'data/subtitles-ocr.sqlite', 'data/TextMapCHS.json', 'data/TextMapEN.json', 'data/TextMap_MediumCHS.json', 'data/TextMap_MediumEN.json')) {
    if (!(Test-Path -LiteralPath (Join-Path $PSScriptRoot $file))) { throw "Missing required file: $file" }
    Write-Output "OK $file"
}
$shell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
& $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'prepare-ocr-index.ps1') -CheckOnly
if ($LASTEXITCODE -ne 0) { throw 'OCR database schema check failed.' }
Write-Output 'OCR database schema: OK'
if ($PSVersionTable.PSEdition -eq 'Core') {
    Write-Warning 'Run with Windows PowerShell 5.1 to check Windows OCR languages.'
} else {
    $languages = @([Windows.Media.Ocr.OcrEngine,Windows.Media.Ocr,ContentType=WindowsRuntime]::AvailableRecognizerLanguages)
    Write-Output ('Windows OCR languages: ' + (($languages | ForEach-Object LanguageTag) -join ', '))
    if (!($languages | Where-Object { $_.LanguageTag -like 'zh*' -or $_.LanguageTag -like 'en*' })) {
        throw 'Install Chinese or English OCR support in Windows language settings.'
    }
}
if ($RunTests) {
    & $python (Join-Path $PSScriptRoot 'tests/ocr_direction_tests.py')
    if ($LASTEXITCODE -ne 0) { throw 'OCR direction tests failed.' }
}
Write-Output 'Environment check passed. Game UI behavior still requires a manual check.'
