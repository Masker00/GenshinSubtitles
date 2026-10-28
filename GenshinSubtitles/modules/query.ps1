function Lookup-Official([string]$Text, [string]$SourceLanguage) {
    if (!$Text) { return [pscustomobject]@{ source = ''; opposite = '' } }
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $encoded = [Convert]::ToBase64String($bytes)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $python
    $psi.WorkingDirectory = $root
    $psi.Arguments = $lookup + ' --db ' + $db + ' --source ' + $SourceLanguage + ' --format json --text-b64 ' + $encoded
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    try {
        [void]$process.Start()
        $output = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit()
        return ($output | ConvertFrom-Json)
    }
    finally {
        $process.Dispose()
    }
}
