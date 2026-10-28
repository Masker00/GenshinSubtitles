param([Parameter(Mandatory=$true)][string]$WorkerRequest)
$ErrorActionPreference = 'Stop'
try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $request = Get-Content -LiteralPath $WorkerRequest -Raw -Encoding UTF8 | ConvertFrom-Json
    $root = Split-Path -Parent $MyInvocation.MyCommand.Path
    . (Join-Path $root 'modules/platform.ps1')
    . (Join-Path $root 'modules/capture.ps1')
    . (Join-Path $root 'modules/query.ps1')
    $python = [string]$request.Python
    $db = 'data/subtitles-ocr.sqlite'
    if ($request.Frame) {
        $current = Get-GameBounds
        $expected = $request.GameBounds
        if (!$current -or [long]$current.Handle -ne [long]$request.WindowHandle -or $current.ProcessId -ne $request.GameProcessId -or
            $current.Left -ne $expected.Left -or $current.Top -ne $expected.Top -or $current.Right -ne $expected.Right -or $current.Bottom -ne $expected.Bottom) {
            throw 'The game window changed before capture.'
        }
        $frame = [Drawing.Rectangle]::new($request.Frame.X,$request.Frame.Y,$request.Frame.Width,$request.Frame.Height)
        Capture-SubtitleRegion $frame $request.ImagePath
    }
    $ocrType = [Windows.Media.Ocr.OcrEngine,Windows.Media.Ocr,ContentType=WindowsRuntime]
    $languageTag = if ($request.Source -eq 'EN') { 'en-US' } else { 'zh-Hans-CN' }
    $language = [Windows.Globalization.Language,Windows.Globalization,ContentType=WindowsRuntime]::new($languageTag)
    $engine = $ocrType::TryCreateFromLanguage($language)
    if (!$engine) {
        $fallback = if ($request.Source -eq 'EN') { 'zh-Hans-CN' } else { 'en-US' }
        $language = [Windows.Globalization.Language,Windows.Globalization,ContentType=WindowsRuntime]::new($fallback)
        $engine = $ocrType::TryCreateFromLanguage($language)
    }
    if (!$engine) { throw "Windows OCR language is unavailable: $languageTag" }
    $text = (Invoke-Ocr $request.ImagePath $engine).Trim()
    $result = @{ text = $text; source = ''; opposite = ''; matched = $false; text_id = $null; method = 'none'; similarity = 0.0; cached = $false }
    if ((Get-VisibleLength $text) -gt 10) {
        $cache = $request.Cache
        if ($cache -and $cache.Matched -and $cache.Text -ceq $text -and $cache.Source -eq $request.Source) {
            $result = @{ text=$text; source=$cache.SourceText; opposite=$cache.Opposite; matched=$true; text_id=$cache.TextId; method=$cache.Method; similarity=$cache.Similarity; cached=$true }
        } else {
            $lookup = Lookup-Official $text $request.Source
            $result.source = $lookup.source; $result.opposite = $lookup.opposite
            $result.matched = $lookup.matched; $result.text_id = $lookup.text_id
            $result.method = $lookup.method; $result.similarity = $lookup.similarity
        }
    }
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress))
} catch {
    [Console]::Error.WriteLine($_.Exception.ToString())
    exit 1
} finally {
    if ($request -and $request.ImagePath -and (Test-Path -LiteralPath $request.ImagePath)) {
        Remove-Item -LiteralPath $request.ImagePath -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $WorkerRequest) { Remove-Item -LiteralPath $WorkerRequest -Force -ErrorAction SilentlyContinue }
}
