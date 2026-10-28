param([string]$DataRoot = '', [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (!$DataRoot) { $DataRoot = Join-Path $root 'data' }
. (Join-Path $PSScriptRoot 'resolve-python.ps1')
$python = Resolve-SubtitlePython
$sources = @('TextMapCHS.json','TextMapEN.json','TextMap_MediumCHS.json','TextMap_MediumEN.json' | ForEach-Object { Join-Path $DataRoot $_ })
$database = Join-Path $DataRoot 'subtitles-ocr.sqlite'
foreach ($source in $sources) {
    if (!(Test-Path -LiteralPath $source -PathType Leaf)) {
        if ($CheckOnly) { exit 1 }
        throw "Missing pinned TextMap source: $source. Run fetch-data.ps1 first."
    }
}
if ($CheckOnly) {
    if (!(Test-Path -LiteralPath $database -PathType Leaf)) { exit 1 }
    $arguments = @((Join-Path $root 'tools/index_schema.py'), '--db', $database)
    foreach ($source in $sources) { $arguments += @('--source', $source) }
    & $python @arguments
    exit $LASTEXITCODE
}
$arguments = @((Join-Path $root 'tools/build_ocr_index.py'), '--chs', $sources[0], '--en', $sources[1],
    '--chs-extra', $sources[2], '--en-extra', $sources[3], '--db', $database)
& $python @arguments
if ($LASTEXITCODE -ne 0) { throw 'OCR index build failed; the previous database remains in place.' }
$checkArguments = @((Join-Path $root 'tools/index_schema.py'), '--db', $database)
foreach ($source in $sources) { $checkArguments += @('--source', $source) }
& $python @checkArguments
if ($LASTEXITCODE -ne 0) { throw 'New OCR index failed its post-build checks.' }
