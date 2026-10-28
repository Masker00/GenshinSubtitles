$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
function Step([string]$Message) { Write-Host "`n== $Message ==" -ForegroundColor Cyan }
function Complete([string]$Message) { Write-Host "  OK  $Message" -ForegroundColor Green }
try {
    Step 'Windows PowerShell'
    if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) {
        throw 'Run this installer with Windows PowerShell 5.1 (Windows PowerShell), not PowerShell 7.'
    }
    Complete 'Windows PowerShell 5.1'

    Step 'Python'
    . (Join-Path $root 'resolve-python.ps1')
    $python = Resolve-SubtitlePython
    & $python --version
    if ($LASTEXITCODE -ne 0) { throw 'Python did not start correctly.' }
    Complete "Python with sqlite3: $python"

    Step 'Windows OCR'
    $languageInfo = Join-Path $env:TEMP ('genshin-ocr-languages-' + [Guid]::NewGuid().ToString('N') + '.json')
    $probe = '$l=@([Windows.Media.Ocr.OcrEngine,Windows.Media.Ocr,ContentType=WindowsRuntime]::AvailableRecognizerLanguages | ForEach-Object LanguageTag); $l | ConvertTo-Json -Compress | Set-Content -Encoding UTF8 -LiteralPath ''' + $languageInfo.Replace("'", "''") + ''''
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command $probe
    if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $languageInfo)) {
        throw 'Could not inspect Windows OCR languages. Check that Windows Media OCR is available.'
    }
    $languages = Get-Content -Raw -LiteralPath $languageInfo -Encoding UTF8 | ConvertFrom-Json
    Remove-Item -LiteralPath $languageInfo -Force
    $available = @($languages | Where-Object { $_ -like 'zh*' -or $_ -like 'en*' })
    if (!$available.Count) {
        throw 'Windows OCR Chinese or English is missing. In Settings > Time & language > Language & region, install Chinese (Simplified) or English language components including Basic typing and OCR, then rerun setup.bat.'
    }
    Complete ('Windows OCR: ' + ($available -join ', '))
    if (!($languages -like 'zh*') -or !($languages -like 'en*')) {
        Write-Warning 'One OCR language is missing. Install both Chinese and English OCR in Windows language options for best recognition; the available engine will be used as a fallback.'
    }

    Step 'Pinned official-text sources'
    $data = Join-Path $root 'data'
    $sources = @('TextMapCHS.json','TextMapEN.json','TextMap_MediumCHS.json','TextMap_MediumEN.json' | ForEach-Object { Join-Path $data $_ })
    & (Join-Path $root 'fetch-data.ps1')
    Complete 'Four files from the pinned game-data commit passed size and Git blob SHA-1 checks'

    Step 'Local SQLite index'
    $prepare = Join-Path $root 'prepare-ocr-index.ps1'
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $prepare -CheckOnly
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'No current index found; building it once from the verified sources.'
        & $prepare
        if ($LASTEXITCODE -ne 0) { throw 'SQLite index creation failed.' }
    } else { Complete 'Existing index is current; skipped download and rebuild' }
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $prepare -CheckOnly
    if ($LASTEXITCODE -ne 0) { throw 'SQLite index validation failed after preparation.' }
    Complete 'Index schema, source fingerprints and SQLite integrity passed'

    Step 'Environment checks and regression tests'
    & (Join-Path $root 'check-environment.ps1') -RunTests
    if ($LASTEXITCODE -ne 0) { throw 'Environment checks or query regressions failed.' }
    Complete 'Setup is complete. Start the game normally, then run GenshinSubtitles\launcher.bat.'
    exit 0
} catch {
    Write-Host ("`nSetup failed: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
