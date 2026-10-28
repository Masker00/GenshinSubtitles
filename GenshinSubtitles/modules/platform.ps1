Add-Type -Path (Join-Path $root 'native/Dpi.cs')
# Keep GetWindowRect, WinForms window bounds and GDI screen capture in physical pixels.
if (![GenshinSubtitleDpiNative]::SetProcessDpiAwarenessContext([IntPtr]::new(-4))) {
    if ([GenshinSubtitleDpiNative]::SetThreadDpiAwarenessContext([IntPtr]::new(-4)) -eq [IntPtr]::Zero) {
        throw 'Could not enable DPI-aware screen coordinates for the OCR overlay.'
    }
}
Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -ReferencedAssemblies 'System.Windows.Forms.dll', 'System.Drawing.dll' -Path (Join-Path $root 'native/OverlayWindows.cs')
Add-Type -Path (Join-Path $root 'native/ScanJob.cs')

function Get-GameBounds {
    $process = @(Get-Process -Name YuanShen,GenshinImpact -ErrorAction SilentlyContinue | Select-Object -First 1)[0]
    if ($process -and $process.MainWindowHandle -ne 0) {
        $rect = New-Object GenshinSubtitleOverlayNative+RECT
        $ok = [GenshinSubtitleOverlayNative]::GetWindowRect($process.MainWindowHandle, [ref]$rect)
        if ($ok -and ![GenshinSubtitleOverlayNative]::IsIconic($process.MainWindowHandle) -and [GenshinSubtitleOverlayNative]::IsWindowVisible($process.MainWindowHandle) -and $rect.Right -gt $rect.Left -and $rect.Bottom -gt $rect.Top) {
            $rect | Add-Member -NotePropertyName ProcessId -NotePropertyValue $process.Id
            $rect | Add-Member -NotePropertyName Handle -NotePropertyValue $process.MainWindowHandle
            Write-Output -NoEnumerate $rect
            return
        }
    }
    return $null
}
