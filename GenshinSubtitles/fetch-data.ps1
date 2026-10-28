param()
$ErrorActionPreference = 'Stop'
# Pinned release data; no moving branch URLs and no automatic update at runtime.
$repo = 'DimbreathBot/AnimeGameData'
$releaseCommit = '9587d1afbd9ab0419cdd00dc05ecd114b9e3fe99'
$release = 'CNRELWin7.1.0_R48145775_S48131320_D48145775'
$files = @(
    @{Name='TextMapCHS.json'; Blob='2f5e815b41f387273d7b8eaf09f00509358e3523'; Bytes=49920231},
    @{Name='TextMapEN.json'; Blob='3d6b3fb277f8b517fb535db83d86345a5cc9c3f1'; Bytes=55719620},
    @{Name='TextMap_MediumCHS.json'; Blob='ddf41a92f596f3f3300d7b0901c2b8f61a3ecb6d'; Bytes=18801724},
    @{Name='TextMap_MediumEN.json'; Blob='e9e278567a37220d46e1a86a0c7876f57f71abd6'; Bytes=20704568}
)
$dataDir = Join-Path $PSScriptRoot 'data'
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
$sources = @()
foreach ($item in $files) {
    $destination = Join-Path $dataDir $item.Name
    if (!(Test-Path -LiteralPath $destination)) {
        $temporary = $destination + '.downloading'
        $uri = 'https://raw.githubusercontent.com/' + $repo + '/' + $releaseCommit + '/TextMap/' + $item.Name
        & curl.exe --fail --location --silent --show-error --compressed --connect-timeout 15 --max-time 90 --output $temporary $uri
        if ($LASTEXITCODE -ne 0) {
            $uri = 'https://api.github.com/repos/' + $repo + '/git/blobs/' + $item.Blob
            & curl.exe --fail --location --silent --show-error --compressed --connect-timeout 15 --max-time 600 --header 'Accept: application/vnd.github.raw+json' --header 'User-Agent: GenshinSubtitles-local-tool' --output $temporary $uri
        }
        if ($LASTEXITCODE -ne 0) { throw ('Download failed or timed out: ' + $item.Name) }
        if ((Get-Item -LiteralPath $temporary).Length -ne $item.Bytes) { throw ('Unexpected download size: ' + $item.Name) }
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
[pscustomobject]@{Repository=$repo;ReleaseCommit=$releaseCommit;Release=$release;Files=$sources;RetrievedUTC=[DateTime]::UtcNow.ToString('o');Credit='Game text: HoYoverse. Community extraction: Dimbreath.'} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'sources.json') -Encoding utf8
