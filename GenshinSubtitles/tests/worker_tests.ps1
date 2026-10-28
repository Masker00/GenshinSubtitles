$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'modules/platform.ps1')
. (Join-Path $root 'resolve-python.ps1')
$python = Resolve-SubtitlePython
$shell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
$folder = Join-Path $root ('test-results/worker-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $folder | Out-Null
$job=$null
function Wait-Worker([SubtitleScanJob]$Job) {
    while (!$Job.Completed) {
        if ($Job.TimedOut) { throw 'Test worker timed out.' }
        [Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 10
    }
    if ($Job.ExitCode -ne 0) { throw $Job.Error }
    return ($Job.Output | ConvertFrom-Json)
}
try {
    # First validate the smallest bounded worker before any OCR integration.
    $slowScript = Join-Path $folder 'slow worker.ps1'
    [IO.File]::WriteAllText($slowScript, 'param([string]$WorkerRequest) Start-Sleep -Milliseconds 1500; [Console]::Out.WriteLine(''{"ok":true}'')')
    $script:pulses=0
    $timer=New-Object Windows.Forms.Timer
    $timer.Interval=20; $timer.Add_Tick({$script:pulses++}); $timer.Start()
    $job=[SubtitleScanJob]::Start($shell,$slowScript,'unused','test',7,8)
    $result=Wait-Worker $job
    $timer.Stop(); $timer.Dispose(); $job.Dispose(); $job=$null
    if (!$result.ok -or $script:pulses -lt 20) { throw 'UI timer was blocked by the background worker.' }
    Write-Output ('Minimal worker and responsive WinForms heartbeat: OK, ticks=' + $script:pulses)

    # Synthetic image, no desktop capture and no personal screen content.
    $imagePath=Join-Path $folder 'ocr fixture.png'
    $bitmap=[Drawing.Bitmap]::new(1500,160)
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    $font=[Drawing.Font]::new('Arial',32)
    try {
        $graphics.Clear([Drawing.Color]::White)
        $graphics.DrawString('Hey, hello! Do you know where Kazuha is?', $font, [Drawing.Brushes]::Black, 15, 45)
        $bitmap.Save($imagePath,[Drawing.Imaging.ImageFormat]::Png)
    } finally { $font.Dispose(); $graphics.Dispose(); $bitmap.Dispose() }
    $requestPath=Join-Path $folder 'request.json'
    @{ImagePath=$imagePath;Python=$python;Source='EN'} | ConvertTo-Json | Set-Content -Encoding UTF8 $requestPath
    $job=[SubtitleScanJob]::Start($shell,(Join-Path $root 'scan-worker.ps1'),$requestPath,'fixture',0,15)
    $result=Wait-Worker $job
    $job.Dispose(); $job=$null
    if (!$result.matched -or $result.text_id -ne '2545425690' -or !$result.source -or !$result.opposite) { throw ('Real Windows OCR + official lookup failed: ' + ($result | ConvertTo-Json)) }
    if ((Test-Path $requestPath) -or (Test-Path $imagePath)) { throw 'OCR worker left request/image resources behind.' }
    Write-Output 'Real Windows OCR image -> Medium bilingual official record: OK'

    # Kill a hung worker and verify its Python descendant is owned by the job.
    $hungScript=Join-Path $folder 'hung worker.ps1'
    $childPidPath=Join-Path $folder 'child.pid'
    $body='param([string]$WorkerRequest) $r=Get-Content -Raw $WorkerRequest | ConvertFrom-Json; $p=Start-Process -FilePath $r.Python -ArgumentList ''-c "import time; time.sleep(120)"'' -WindowStyle Hidden -PassThru; [IO.File]::WriteAllText($r.PidPath,[string]$p.Id); Start-Sleep -Seconds 120'
    [IO.File]::WriteAllText($hungScript,$body)
    @{Python=$python;PidPath=$childPidPath} | ConvertTo-Json | Set-Content -Encoding UTF8 $requestPath
    $job=[SubtitleScanJob]::Start($shell,$hungScript,$requestPath,'hung',0,2)
    $parentPid=$job.ProcessId
    while (!$job.TimedOut) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 }
    if (!(Test-Path $childPidPath)) { throw 'Hung worker did not spawn the cleanup test child.' }
    $childPid=[int](Get-Content $childPidPath)
    $job.Dispose(); $job=$null
    $until=[DateTime]::UtcNow.AddSeconds(3)
    while ((Get-Process -Id $childPid -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $until) { Start-Sleep -Milliseconds 20 }
    if ((Get-Process -Id $parentPid,$childPid -ErrorAction SilentlyContinue)) { throw 'Worker or child process leaked after cancellation.' }
    $job=[SubtitleScanJob]::Start($shell,$slowScript,'unused','recovered',1,8)
    $result=Wait-Worker $job
    $job.Dispose(); $job=$null
    if (!$result.ok) { throw 'Worker failed to recover after timeout.' }
    Write-Output 'Timeout, descendant cleanup and subsequent worker recovery: OK'
} finally {
    if ($job) { $job.Dispose() }
    Remove-Item -LiteralPath $folder -Recurse -Force
}
