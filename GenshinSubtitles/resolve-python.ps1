function Resolve-SubtitlePython {
    # Return a real interpreter path, never a launcher or Windows Store alias.
    $candidates = @()
    if ($env:GENSHIN_SUBTITLES_PYTHON) {
        $candidates = @($env:GENSHIN_SUBTITLES_PYTHON)
    } else {
        $candidates += (Join-Path $PSScriptRoot '.venv/Scripts/python.exe')
        $candidates += (Join-Path $PSScriptRoot 'runtime/python/python.exe')
        foreach ($name in @('python.exe', 'python3.exe', 'py.exe')) {
            $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($command) { $candidates += $command.Source }
        }

    }
    foreach ($candidate in $candidates) {
        if (!(Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $arguments = @('-c', 'import sys,sqlite3; assert sys.version_info >= (3,9); print(sys.executable)')
        if ([IO.Path]::GetFileName($candidate) -eq 'py.exe') { $arguments = @('-3') + $arguments }
        try {
            $resolved = @(& $candidate @arguments 2>$null)
            if ($LASTEXITCODE -eq 0 -and $resolved.Count -gt 0) {
                $path = [string]$resolved[-1]
                if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
            }
        } catch { }
    }
    throw 'Python 3.9+ with sqlite3 is required. Install Python (add to PATH), or set GENSHIN_SUBTITLES_PYTHON to its python.exe path.'
}
