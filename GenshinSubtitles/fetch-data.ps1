param()
$ErrorActionPreference = 'Stop'
# Pinned release data; no moving branch URLs and no automatic update at runtime.
$dataDir = Join-Path $PSScriptRoot 'data'
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
$manifest = Get-Content -LiteralPath (Join-Path $dataDir 'sources.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$repo = [string]$manifest.repository
$releaseCommit = [string]$manifest.commit
$release = [string]$manifest.release
$files = @($manifest.files | ForEach-Object { @{Name=$_.name; Blob=$_.gitBlob; Bytes=[long]$_.bytes} })
$sources = @()
$receiptDir = Join-Path $PSScriptRoot '..\.local'
New-Item -ItemType Directory -Force -Path $receiptDir | Out-Null
foreach ($item in $files) {
    $destination = Join-Path $dataDir $item.Name
    if (Test-Path -LiteralPath $destination) {
        $bytes = [IO.File]::ReadAllBytes($destination)
        $prefix = [Text.Encoding]::ASCII.GetBytes('blob ' + $bytes.Length + [char]0)
        $hash = [Security.Cryptography.SHA1]::Create()
        $null = $hash.TransformBlock($prefix,0,$prefix.Length,$prefix,0)
        $null = $hash.TransformFinalBlock($bytes,0,$bytes.Length)
        $existing = [BitConverter]::ToString($hash.Hash).Replace('-','').ToLowerInvariant()
        $hash.Dispose()
        if ($bytes.Length -ne $item.Bytes -or $existing -ne $item.Blob) {
            $backup = $destination + '.invalid-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
            Move-Item -LiteralPath $destination -Destination $backup
            Write-Output ('Preserved invalid data as ' + $backup)
        }
    }
    if (!(Test-Path -LiteralPath $destination)) {
        $temporary = $destination + '.downloading'
        $uri = 'https://raw.githubusercontent.com/' + $repo + '/' + $releaseCommit + '/TextMap/' + $item.Name
        Write-Output ('Downloading ' + $item.Name + ' (' + $item.Bytes + ' bytes), fixed commit ' + $releaseCommit)
        & curl.exe --fail --location --silent --show-error --connect-timeout 15 --max-time 600 --speed-limit 1024 --speed-time 30 --output $temporary $uri
        if ($LASTEXITCODE -ne 0) {
            $uri = 'https://api.github.com/repos/' + $repo + '/git/blobs/' + $item.Blob
            Write-Output ('Retrying the same pinned Git blob through GitHub API: ' + $item.Name)
            & curl.exe --fail --location --silent --show-error --connect-timeout 15 --max-time 600 --speed-limit 1024 --speed-time 30 --header 'Accept: application/vnd.github.raw+json' --header 'User-Agent: GenshinSubtitles-local-tool' --output $temporary $uri
        }
        if ($LASTEXITCODE -ne 0) { throw ('Download failed or timed out: ' + $item.Name) }
        if ((Get-Item -LiteralPath $temporary).Length -ne $item.Bytes) { throw ('Unexpected download size: ' + $item.Name) }
        $download = [IO.File]::ReadAllBytes($temporary)
        $downloadPrefix = [Text.Encoding]::ASCII.GetBytes('blob ' + $download.Length + [char]0)
        $downloadHash = [Security.Cryptography.SHA1]::Create()
        $null = $downloadHash.TransformBlock($downloadPrefix,0,$downloadPrefix.Length,$downloadPrefix,0)
        $null = $downloadHash.TransformFinalBlock($download,0,$download.Length)
        $downloadBlob = [BitConverter]::ToString($downloadHash.Hash).Replace('-','').ToLowerInvariant()
        $downloadHash.Dispose()
        if ($downloadBlob -ne $item.Blob) { Remove-Item -LiteralPath $temporary -Force; throw ('Git blob SHA1 mismatch: ' + $item.Name) }
        Move-Item -LiteralPath $temporary -Destination $destination
    }
    $bytes = [IO.File]::ReadAllBytes($destination)
    $prefix = [Text.Encoding]::ASCII.GetBytes('blob ' + $bytes.Length + [char]0)
    $hash = [Security.Cryptography.SHA1]::Create()
    $null = $hash.TransformBlock($prefix,0,$prefix.Length,$prefix,0)
    $null = $hash.TransformFinalBlock($bytes,0,$bytes.Length)
    $actual = [BitConverter]::ToString($hash.Hash).Replace('-','').ToLowerInvariant()
    $hash.Dispose()
    if ($actual -ne $item.Blob) { throw ('Git blob SHA1 mismatch: ' + $item.Name) }
    $sources += [pscustomobject]@{File=$item.Name;Bytes=$bytes.Length;GitBlob=$actual;SHA256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()}
    Write-Output ('Verified ' + $item.Name + ': ' + $bytes.Length + ' bytes')
}
[pscustomobject]@{Repository=$repo;ReleaseCommit=$releaseCommit;Release=$release;Files=$sources;RetrievedUTC=[DateTime]::UtcNow.ToString('o');Credit='Game text: HoYoverse. Community extraction: Dimbreath.'} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $receiptDir 'data-receipt.json') -Encoding utf8
