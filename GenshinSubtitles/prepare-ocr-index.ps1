param(
    [string]$DataRoot = '',
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (!$DataRoot) { $DataRoot = $root + '/data' }
. (Join-Path $PSScriptRoot 'resolve-python.ps1')
$python = Resolve-SubtitlePython
$builder = $root + '/tools/build_ocr_index.py'
$chs = $DataRoot + '/TextMapCHS.json'
$en = $DataRoot + '/TextMapEN.json'
$chsExtra = $DataRoot + '/TextMap_MediumCHS.json'
$enExtra = $DataRoot + '/TextMap_MediumEN.json'
$db = $DataRoot + '/subtitles-ocr.sqlite'
if ($CheckOnly) {
    if (!(Test-Path -LiteralPath $db)) { exit 1 }
    foreach ($source in @($chs, $en, $chsExtra, $enExtra)) {
        if (!(Test-Path -LiteralPath $source)) { exit 1 }
        if ((Get-Item -LiteralPath $source).LastWriteTimeUtc -gt (Get-Item -LiteralPath $db).LastWriteTimeUtc) { exit 1 }
    }
    & $python -c "import sqlite3,sys; db=sqlite3.connect('file:'+sys.argv[1]+'?mode=ro',uri=True); names={r[0] for r in db.execute('select name from sqlite_master')}; columns={r[1] for r in db.execute('pragma table_info(english_subtitle)')} if 'english_subtitle' in names else set(); extra=db.execute('select value from metadata where key=?',('extra_pairs',)).fetchone() if 'metadata' in names else None; sys.exit(0 if {'subtitle','english_subtitle'} <= names and {'en_key','en','zh'} <= columns and extra == ('1',) else 1)" $db
    exit $LASTEXITCODE
}
if (!(Test-Path -LiteralPath $chs) -or !(Test-Path -LiteralPath $en) -or !(Test-Path -LiteralPath $chsExtra) -or !(Test-Path -LiteralPath $enExtra)) {
    throw 'Base and Medium Chinese/English TextMap pairs are required. Run fetch-data.ps1 first.'
}
& $python $builder --chs $chs --en $en --chs-extra $chsExtra --en-extra $enExtra --db $db
if ($LASTEXITCODE -ne 0) { throw 'OCR index build failed.' }
