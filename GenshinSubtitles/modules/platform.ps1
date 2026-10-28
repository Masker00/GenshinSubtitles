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

function Get-GameBounds {
    $process = @(Get-Process -Name YuanShen,GenshinImpact -ErrorAction SilentlyContinue | Select-Object -First 1)[0]
    if ($process -and $process.MainWindowHandle -ne 0) {
        $rect = New-Object GenshinSubtitleOverlayNative+RECT
        $ok = [GenshinSubtitleOverlayNative]::GetWindowRect($process.MainWindowHandle, [ref]$rect)
        if ($ok) {
            Write-Output -NoEnumerate $rect
            return
        }
    }
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $fallback = New-Object GenshinSubtitleOverlayNative+RECT
    [void]($fallback.Left = $screen.Left)
    [void]($fallback.Top = $screen.Top)
    [void]($fallback.Right = $screen.Right)
    [void]($fallback.Bottom = $screen.Bottom)
    Write-Output -NoEnumerate $fallback
}
