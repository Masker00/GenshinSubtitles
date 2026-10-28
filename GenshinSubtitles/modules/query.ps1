function Lookup-Official([string]$Text, [string]$SourceLanguage) {
    if (!$Text) { return [pscustomobject]@{ matched=$false; source=''; opposite='' } }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text))
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $python
    $psi.WorkingDirectory = $root
    $psi.Arguments = '-X utf8 "' + (Join-Path $root 'tools/lookup_ocr_text.py') + '" --db "' + (Join-Path $root 'data/subtitles-ocr.sqlite') + '" --source ' + $SourceLanguage + ' --format json --text-b64 ' + $encoded
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    try {
        [void]$process.Start()
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        if (!$process.WaitForExit(10000)) { $process.Kill(); throw 'Official-text lookup timed out after 10 seconds.' }
        if ($process.ExitCode -ne 0) { throw ('Official-text lookup failed: ' + $errTask.GetAwaiter().GetResult()) }
        return ($outTask.GetAwaiter().GetResult() | ConvertFrom-Json)
    } finally {
        try { if (!$process.HasExited) { $process.Kill() }; [void]$process.WaitForExit(1000) } catch {}
        $process.Dispose()
    }
}
