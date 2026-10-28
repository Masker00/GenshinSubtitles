param(
    [string]$ExpectedExe = '',
    [switch]$CheckOnly,
    [switch]$UiCheck
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $PSScriptRoot 'resolve-python.ps1')
$python = Resolve-SubtitlePython
$lookup = 'tools/lookup_ocr_text.py'
$db = 'data/subtitles-ocr.sqlite'
if (!(Test-Path -LiteralPath ($root + '/' + $db))) {
    throw 'OCR index is missing. Run prepare-ocr-index.ps1 first.'
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GenshinSubtitleDpiNative {
    [DllImport("user32.dll", SetLastError=true)] public static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
}
'@
# Keep GetWindowRect, WinForms window bounds and GDI screen capture in physical pixels.
if (![GenshinSubtitleDpiNative]::SetProcessDpiAwarenessContext([IntPtr]::new(-4))) {
    if ([GenshinSubtitleDpiNative]::SetThreadDpiAwarenessContext([IntPtr]::new(-4)) -eq [IntPtr]::Zero) {
        throw 'Could not enable DPI-aware screen coordinates for the OCR overlay.'
    }
}
Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -ReferencedAssemblies 'System.Windows.Forms.dll', 'System.Drawing.dll' -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GenshinSubtitleOverlayNative {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(System.Drawing.Point point);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hWnd, int index);
    [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr hWnd, int index, int value);
    public static void MakeNoActivate(IntPtr hWnd) {
        int style = GetWindowLong(hWnd, -20);
        SetWindowLong(hWnd, -20, style | 0x20 | 0x08000000);
    }
}
public class GenshinSubtitleToolbarForm : System.Windows.Forms.Form {
    public bool Collapsed { get; set; }
    public bool IsDragging { get; private set; }
    public System.Drawing.Rectangle MovementBounds { get; set; }
    public event EventHandler DragCompleted;
    public event EventHandler RestoreRequested;
    private System.Drawing.Point start, original;
    private bool moved;
    public GenshinSubtitleToolbarForm() { DoubleBuffered = true; }
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override void OnMouseDown(System.Windows.Forms.MouseEventArgs e) {
        base.OnMouseDown(e);
        if (e.Button != System.Windows.Forms.MouseButtons.Left) return;
        start = PointToScreen(e.Location); original = Location;
        moved = false; IsDragging = true; Capture = true;
    }
    protected override void OnMouseMove(System.Windows.Forms.MouseEventArgs e) {
        base.OnMouseMove(e);
        Cursor = System.Windows.Forms.Cursors.SizeAll;
        if (!IsDragging) return;
        var p = PointToScreen(e.Location);
        int dx = p.X - start.X, dy = p.Y - start.Y;
        if (Math.Abs(dx) > 4 || Math.Abs(dy) > 4) moved = true;
        if (!moved) return;
        var bounds = MovementBounds;
        Location = new System.Drawing.Point(
            Math.Max(bounds.Left, Math.Min(bounds.Right - Width, original.X + dx)),
            Math.Max(bounds.Top, Math.Min(bounds.Bottom - Height, original.Y + dy)));
    }
    protected override void OnMouseUp(System.Windows.Forms.MouseEventArgs e) {
        base.OnMouseUp(e);
        if (e.Button != System.Windows.Forms.MouseButtons.Left || !IsDragging) return;
        IsDragging = false; Capture = false;
        if (moved) { if (DragCompleted != null) DragCompleted(this, EventArgs.Empty); }
        else if (Collapsed && RestoreRequested != null) RestoreRequested(this, EventArgs.Empty);
    }
    protected override void OnMouseCaptureChanged(EventArgs e) {
        base.OnMouseCaptureChanged(e);
        if (!Capture && IsDragging) {
            IsDragging = false;
            if (moved && DragCompleted != null) DragCompleted(this, EventArgs.Empty);
        }
    }
    protected override void OnPaint(System.Windows.Forms.PaintEventArgs e) {
        base.OnPaint(e);
        if (Collapsed) {
            using (var font = new System.Drawing.Font("Segoe MDL2 Assets", 18)) {
                System.Windows.Forms.TextRenderer.DrawText(e.Graphics, "\uE8F2", font, ClientRectangle,
                    System.Drawing.Color.FromArgb(30, 70, 90),
                    System.Windows.Forms.TextFormatFlags.HorizontalCenter | System.Windows.Forms.TextFormatFlags.VerticalCenter);
            }
        } else {
            for (int y = 12; y <= 28; y += 8)
                for (int x = 7; x <= 13; x += 6)
                    e.Graphics.FillRectangle(System.Drawing.Brushes.Gray, x, y, 2, 2);
        }
    }
}
public class GenshinSubtitleClickThroughForm : System.Windows.Forms.Form {
    public bool ClickThrough { get; set; }
    public GenshinSubtitleClickThroughForm() { ClickThrough = true; }
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override void WndProc(ref System.Windows.Forms.Message message) {
        if (message.Msg == 0x84 && ClickThrough) { message.Result = new IntPtr(-1); return; }
        base.WndProc(ref message);
        if (message.Msg == 0x84 && !ClickThrough && message.Result == new IntPtr(1)) {
            message.Result = new IntPtr(2);
        }
    }
}
public class GenshinSubtitleCropForm : GenshinSubtitleSelectionForm {
    public GenshinSubtitleCropForm() {
        BackColor = System.Drawing.Color.FromArgb(130, 110, 25);
        SelectionColor = System.Drawing.Color.FromArgb(255, 225, 50);
    }
}
public class GenshinSubtitleSelectionForm : System.Windows.Forms.Form {
    public System.Drawing.Color SelectionColor { get; set; }
    public event EventHandler BoundsEdited;
    public event EventHandler EditCompleted;
    public System.Drawing.Rectangle MovementBounds { get; set; }
    public bool IsDragging { get; private set; }
    private int edges;
    private System.Drawing.Point start;
    private System.Drawing.Rectangle original;
    public GenshinSubtitleSelectionForm() {
        FormBorderStyle = System.Windows.Forms.FormBorderStyle.None;
        StartPosition = System.Windows.Forms.FormStartPosition.Manual;
        ShowInTaskbar = false; TopMost = true;
        BackColor = System.Drawing.Color.FromArgb(25, 90, 130);
        Opacity = 0.45;
        SelectionColor = System.Drawing.Color.White;
        DoubleBuffered = true;
        SetStyle(System.Windows.Forms.ControlStyles.ResizeRedraw, true);
    }
    protected override bool ShowWithoutActivation { get { return true; } }
    private int HitEdges(System.Drawing.Point p) {
        return (p.X < 12 ? 1 : p.X >= Width - 12 ? 2 : 0) |
               (p.Y < 12 ? 4 : p.Y >= Height - 12 ? 8 : 0);
    }
    protected override void OnMouseDown(System.Windows.Forms.MouseEventArgs e) {
        base.OnMouseDown(e);
        if (e.Button != System.Windows.Forms.MouseButtons.Left) return;
        edges = HitEdges(e.Location); start = PointToScreen(e.Location); original = Bounds;
        IsDragging = true; Capture = true;
    }
    protected override void OnMouseMove(System.Windows.Forms.MouseEventArgs e) {
        base.OnMouseMove(e);
        int hit = IsDragging ? edges : HitEdges(e.Location);
        Cursor = hit == 5 || hit == 10 ? System.Windows.Forms.Cursors.SizeNWSE :
                 hit == 6 || hit == 9 ? System.Windows.Forms.Cursors.SizeNESW :
                 (hit & 3) != 0 ? System.Windows.Forms.Cursors.SizeWE :
                 (hit & 12) != 0 ? System.Windows.Forms.Cursors.SizeNS : System.Windows.Forms.Cursors.SizeAll;
        if (!IsDragging) return;
        var point = PointToScreen(e.Location);
        int dx = point.X - start.X, dy = point.Y - start.Y;
        var limit = MovementBounds;
        int l = original.Left, t = original.Top, r = original.Right, b = original.Bottom;
        int minW = Math.Min(Math.Max(128, (int)Math.Ceiling(limit.Width * 0.05)), limit.Width);
        int minH = Math.Min(Math.Max(64, (int)Math.Ceiling(limit.Height * 0.05)), limit.Height);
        if (edges == 0) {
            l = Math.Max(limit.Left, Math.Min(limit.Right - original.Width, l + dx));
            t = Math.Max(limit.Top, Math.Min(limit.Bottom - original.Height, t + dy));
            r = l + original.Width; b = t + original.Height;
        } else {
            if ((edges & 1) != 0) l = Math.Max(limit.Left, Math.Min(r - minW, l + dx));
            if ((edges & 2) != 0) r = Math.Min(limit.Right, Math.Max(l + minW, r + dx));
            if ((edges & 4) != 0) t = Math.Max(limit.Top, Math.Min(b - minH, t + dy));
            if ((edges & 8) != 0) b = Math.Min(limit.Bottom, Math.Max(t + minH, b + dy));
        }
        Bounds = System.Drawing.Rectangle.FromLTRB(l, t, r, b);
        if (BoundsEdited != null) BoundsEdited(this, EventArgs.Empty);
    }
    private void EndEdit() {
        if (!IsDragging) return;
        IsDragging = false; Capture = false;
        if (EditCompleted != null) EditCompleted(this, EventArgs.Empty);
    }
    protected override void OnMouseUp(System.Windows.Forms.MouseEventArgs e) {
        base.OnMouseUp(e);
        if (e.Button == System.Windows.Forms.MouseButtons.Left) EndEdit();
    }
    protected override void OnMouseCaptureChanged(EventArgs e) {
        base.OnMouseCaptureChanged(e);
        if (!Capture) EndEdit();
    }
    protected override void OnPaint(System.Windows.Forms.PaintEventArgs e) {
        base.OnPaint(e);
        using (var pen = new System.Drawing.Pen(SelectionColor, 2)) {
            e.Graphics.DrawRectangle(pen, 1, 1, Width - 3, Height - 3);
        }
        foreach (int x in new int[] { 1, Width / 2 - 4, Width - 9 })
            foreach (int y in new int[] { 1, Height / 2 - 4, Height - 9 })
                if (x != Width / 2 - 4 || y != Height / 2 - 4)
                    using (var brush = new System.Drawing.SolidBrush(SelectionColor))
                        e.Graphics.FillRectangle(brush, x, y, 8, 8);
    }
}
'@

function Await-WinRT([object]$Operation, [type]$ResultType) {
    $method = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.IsGenericMethodDefinition -and $_.GetGenericArguments().Count -eq 1 -and $_.GetParameters().Count -eq 1
    } | Select-Object -First 1
    $task = $method.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    return $task.GetAwaiter().GetResult()
}

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

$settingsPath = Join-Path $root 'data/overlay-settings.json'
$settingsExistedAtStartup = Test-Path -LiteralPath $settingsPath
$config = @{
    Left = 16.5; Top = 84; Width = 67; Height = 9.5
    FontSize = 24; ShowFrame = $true
    DisplayLeft = 16.5; DisplayTop = 93.5; DisplayWidth = 67; DisplayHeight = 5.5
    DisplayGap = 12; TextPadding = 16
    PluginLanguage = 'ZH'; RecognitionLanguage = 'EN'; SubtitleLanguage = 'EN'
}
$hasSavedDisplayTop = $true
$config.ToolbarLeft = -1.0; $config.ToolbarTop = -1.0; $config.ToolbarCollapsed = $false
if ($settingsExistedAtStartup) {
    try {
        $saved = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($name in @('Left', 'Top', 'Width', 'Height', 'FontSize', 'DisplayLeft', 'DisplayTop', 'DisplayWidth', 'DisplayHeight', 'DisplayGap', 'TextPadding', 'ToolbarLeft', 'ToolbarTop')) {
            if ($null -ne $saved.$name) { $config[$name] = [double]$saved.$name }
        }
        $hasSavedDisplayTop = $null -ne $saved.DisplayTop
        if ($null -ne $saved.ShowFrame) { $config.ShowFrame = [bool]$saved.ShowFrame }
        if ($null -ne $saved.ToolbarCollapsed) { $config.ToolbarCollapsed = [bool]$saved.ToolbarCollapsed }
        if ($saved.PluginLanguage -in @('ZH', 'EN')) { $config.PluginLanguage = [string]$saved.PluginLanguage }
        if ($saved.RecognitionLanguage -in @('ZH', 'EN')) {
            $config.RecognitionLanguage = [string]$saved.RecognitionLanguage
        } elseif ($saved.SourceLanguage -in @('ZH', 'EN')) {
            # Preserve the input direction chosen by older versions.
            $config.RecognitionLanguage = [string]$saved.SourceLanguage
        }
        if ($saved.SubtitleLanguage -in @('ZH', 'EN')) { $config.SubtitleLanguage = [string]$saved.SubtitleLanguage }
    } catch {
        Add-Content -LiteralPath (Join-Path $root 'overlay-errors.log') -Value ((Get-Date -Format o) + ' Invalid settings: ' + $_.Exception.Message)
    }
}
$config.Left = [Math]::Max(0.0, [Math]::Min(95.0, [double]$config.Left))
$config.Top = [Math]::Max(0.0, [Math]::Min(95.0, [double]$config.Top))
$config.Width = [Math]::Max(5.0, [Math]::Min(100.0, [double]$config.Width))
$config.Height = [Math]::Max(5.0, [Math]::Min(100.0, [double]$config.Height))
$config.Width = [Math]::Min([double]$config.Width, 100.0 - $config.Left)
$config.Height = [Math]::Min([double]$config.Height, 100.0 - $config.Top)
$config.FontSize = [Math]::Max(12, [Math]::Min(48, $config.FontSize))
$config.DisplayLeft = [Math]::Max(0.0, [Math]::Min(95.0, $config.DisplayLeft))
$config.DisplayTop = if ($hasSavedDisplayTop) {
    [Math]::Max(0.0, [Math]::Min(95.0, $config.DisplayTop))
} else {
    [Math]::Max(0, [Math]::Min(95, $config.Top - $config.DisplayHeight - 2))
}
$config.DisplayWidth = [Math]::Max(5.0, [Math]::Min(100.0 - $config.DisplayLeft, $config.DisplayWidth))
$config.DisplayHeight = [Math]::Max(5.0, [Math]::Min(100.0, $config.DisplayHeight))
$config.DisplayGap = [Math]::Max(0, [Math]::Min(200, $config.DisplayGap))
$config.TextPadding = [Math]::Max(0, [Math]::Min(40, $config.TextPadding))
$freshDefaultsApplied = !$settingsExistedAtStartup -and $config.Left -eq 16.5 -and $config.Top -eq 84 -and $config.Width -eq 67 -and $config.Height -eq 9.5 -and
    $config.FontSize -eq 24 -and $config.DisplayLeft -eq 16.5 -and $config.DisplayTop -eq 93.5 -and $config.DisplayWidth -eq 67 -and
    $config.DisplayHeight -eq 5.5 -and $config.TextPadding -eq 16 -and $config.PluginLanguage -eq 'ZH' -and
    $config.RecognitionLanguage -eq 'EN' -and $config.SubtitleLanguage -eq 'EN'

function Save-OverlaySettings {
    $savePath = if ($UiCheck) { Join-Path $root 'test-results/overlay-ui-settings.json' } else { $settingsPath }
    $config | ConvertTo-Json | Set-Content -LiteralPath $savePath -Encoding UTF8
}

function Get-CropRectangle([object]$Bounds) {
    $left = [int](@($Bounds.Left)[0]); $top = [int](@($Bounds.Top)[0])
    $width = [Math]::Max(640, [int](@($Bounds.Right)[0]) - $left)
    $height = [Math]::Max(360, [int](@($Bounds.Bottom)[0]) - $top)
    $x = $left + [int]($width * $config.Left / 100)
    $y = $top + [int]($height * $config.Top / 100)
    $w = [Math]::Max(20, [int]($width * [Math]::Min($config.Width, 100 - $config.Left) / 100))
    $h = [Math]::Max(20, [int]($height * [Math]::Min($config.Height, 100 - $config.Top) / 100))
    return [Drawing.Rectangle]::new($x, $y, $w, $h)
}

function Get-CaptureRectangle([Drawing.Rectangle]$FrameBounds) {
    # Leave the painted border outside the OCR pixels.
    return [Drawing.Rectangle]::new($FrameBounds.Left + 5, $FrameBounds.Top + 5, $FrameBounds.Width - 10, $FrameBounds.Height - 10)
}

function Get-CropFrameScreenBounds {
    $rect = New-Object GenshinSubtitleOverlayNative+RECT
    if (![GenshinSubtitleOverlayNative]::GetWindowRect($cropFrame.Handle, [ref]$rect)) {
        throw 'Could not locate the OCR frame on screen.'
    }
    return [Drawing.Rectangle]::FromLTRB($rect.Left, $rect.Top, $rect.Right, $rect.Bottom)
}

function Capture-SubtitleRegion([Drawing.Rectangle]$FrameBounds, [string]$Path) {
    $crop = Get-CaptureRectangle $FrameBounds
    $bitmap = New-Object System.Drawing.Bitmap($crop.Width, $crop.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($crop.Left, $crop.Top, 0, 0, $bitmap.Size)
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Invoke-Ocr([string]$Path, [object]$Engine) {
    $storageFileType = [Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]
    $streamType = [Windows.Storage.Streams.IRandomAccessStreamWithContentType,Windows.Storage,ContentType=WindowsRuntime]
    $decoderType = [Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics,ContentType=WindowsRuntime]
    $softwareBitmapType = [Windows.Graphics.Imaging.SoftwareBitmap,Windows.Graphics,ContentType=WindowsRuntime]
    $ocrResultType = [Windows.Media.Ocr.OcrResult,Windows.Media,ContentType=WindowsRuntime]
    $storageFile = Await-WinRT ([Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]::GetFileFromPathAsync($Path)) $storageFileType
    $stream = Await-WinRT ($storageFile.OpenReadAsync()) $streamType
    try {
        $decoder = Await-WinRT ([Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics,ContentType=WindowsRuntime]::CreateAsync($stream)) $decoderType
        $softwareBitmap = Await-WinRT ($decoder.GetSoftwareBitmapAsync()) $softwareBitmapType
        $result = Await-WinRT ($Engine.RecognizeAsync($softwareBitmap)) $ocrResultType
        return [string]$result.Text
    }
    finally {
        if ($stream) { try { $stream.Dispose() } catch {} }
    }
}

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

function Get-VisibleLength([string]$Text) {
    $compact = [regex]::Replace($Text, '\s+', '')
    if (!$compact) { return 0 }
    return [System.Globalization.StringInfo]::ParseCombiningCharacters($compact).Length
}

$ocrType = [Windows.Media.Ocr.OcrEngine,Windows.Media.Ocr,ContentType=WindowsRuntime]
$zhLanguage = [Windows.Globalization.Language,Windows.Globalization,ContentType=WindowsRuntime]::new('zh-Hans-CN')
$enLanguage = [Windows.Globalization.Language,Windows.Globalization,ContentType=WindowsRuntime]::new('en-US')
$zhEngine = $ocrType::TryCreateFromLanguage($zhLanguage)
$enEngine = $ocrType::TryCreateFromLanguage($enLanguage)
if (!$zhEngine -and !$enEngine) { throw 'Neither Chinese nor English Windows OCR is available.' }
if ($CheckOnly) {
    $testForm = New-Object GenshinSubtitleClickThroughForm
    $testForm.Dispose()
    [pscustomobject]@{ ocr = 'available'; chinese = [bool]$zhEngine; english = [bool]$enEngine; english_fallback = (!$enEngine -and [bool]$zhEngine); form = 'available' } | ConvertTo-Json
    exit 0
}
$tempImage = ([IO.Path]::GetTempPath() + 'genshin-subtitle-overlay.png')
$state = @{ Enabled = $true; Language = $config.SubtitleLanguage; Busy = $false; LastOcr = ''; LastLookup = ''; LastSource = ''; LastOpposite = ''; LastBounds = $null; Misses = 0; LayoutKey = ''; MeasuredHeight = 0; SettingsPreview = $false; SettingsPreviousText = ''; SettingsPreviousVisible = $false }

$uiStrings = @{
    EN = @{
        SettingsTitle = 'Subtitle settings'; OcrTab = 'OCR'; SubtitleTab = 'Subtitle'
        OcrLeft = 'OCR left (%)'; OcrTop = 'OCR top (%)'; OcrWidth = 'OCR width (%)'; OcrHeight = 'OCR height (%)'
        PluginLanguage = 'Plugin language'; RecognitionLanguage = 'Recognition language'; SubtitleLanguage = 'Subtitle language after recognition'
        Chinese = 'Chinese'; English = 'English'; MaxFontSize = 'Maximum font size'
        SubtitleLeft = 'Subtitle left (%)'; SubtitleTop = 'Subtitle top (%)'; SubtitleWidth = 'Subtitle width (%)'; SubtitleHeight = 'Subtitle height (%)'; TextPadding = 'Text padding (px)'
        DragHint = 'Drag inside the blue selection to move. Drag any edge or corner to resize. Release to save position and size.'
        ShowOcrSelection = 'Show draggable OCR selection'; OcrIdle = 'OCR: select Preview OCR crop to inspect the captured pixels'
        PreviewOcr = 'Preview OCR crop'; Reset = 'Reset'; Close = 'Close'; Settings = 'SET'; Exit = 'EXIT'
        HideToolbar = 'Hide toolbar'; DragToolbar = 'Drag to move'; ShowToolbar = 'Show toolbar; drag to move'
        DragSubtitle = 'Drag subtitle to position'; PreviewInput = 'Preview: actual OCR input'; PreviewError = 'Preview error'
        OcrNoText = 'OCR: no text in frame'; OcrShort = 'OCR (10 or fewer characters)'; Official = 'Official'; NoMatch = '(no match)'; OcrError = 'OCR error'
    }
    ZH = @{
        SettingsTitle = '字幕设置'; OcrTab = '识别'; SubtitleTab = '字幕'
        OcrLeft = '识别区域左侧 (%)'; OcrTop = '识别区域顶部 (%)'; OcrWidth = '识别区域宽度 (%)'; OcrHeight = '识别区域高度 (%)'
        PluginLanguage = '插件语言'; RecognitionLanguage = '识别语言'; SubtitleLanguage = '识别后字幕语言'
        Chinese = '中文'; English = '英文'; MaxFontSize = '最大字体大小'
        SubtitleLeft = '字幕左侧 (%)'; SubtitleTop = '字幕顶部 (%)'; SubtitleWidth = '字幕宽度 (%)'; SubtitleHeight = '字幕高度 (%)'; TextPadding = '文字边距 (px)'
        DragHint = '拖动蓝色选区内部可移动；拖动任意边或角可缩放；松开后自动保存位置和大小。'
        ShowOcrSelection = '显示可拖动的识别选区'; OcrIdle = 'OCR：点击“预览识别区域”检查实际截图'
        PreviewOcr = '预览识别区域'; Reset = '重置'; Close = '关闭'; Settings = '设置'; Exit = '退出'
        HideToolbar = '收起工具栏'; DragToolbar = '拖动以移动'; ShowToolbar = '展开工具栏；拖动以移动'
        DragSubtitle = '拖动字幕以调整位置'; PreviewInput = '预览：实际 OCR 输入'; PreviewError = '预览错误'
        OcrNoText = 'OCR：识别区域内没有文字'; OcrShort = 'OCR（不超过 10 个字符）'; Official = '官方'; NoMatch = '（未匹配）'; OcrError = 'OCR 错误'
    }
}
function Get-UiText([string]$Name) { return [string]$uiStrings[$config.PluginLanguage][$Name] }
function Get-LanguageName([string]$Language) { if ($Language -eq 'EN') { return Get-UiText 'English' } return Get-UiText 'Chinese' }

$subtitle = New-Object GenshinSubtitleClickThroughForm
$subtitle.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$subtitle.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$subtitle.ShowInTaskbar = $false
$subtitle.TopMost = $true
$subtitle.BackColor = [Drawing.Color]::Magenta
$subtitle.TransparencyKey = [Drawing.Color]::Magenta
$subtitle.Opacity = 1.0
$label = New-Object System.Windows.Forms.Label
$label.Dock = [System.Windows.Forms.DockStyle]::Fill
$label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$label.ForeColor = [Drawing.Color]::White
$label.BackColor = [Drawing.Color]::Transparent
$label.Font = [Drawing.Font]::new('Microsoft YaHei UI', [single]$config.FontSize, [Drawing.FontStyle]::Bold)
$label.Padding = New-Object System.Windows.Forms.Padding($config.TextPadding)
$label.AutoEllipsis = $false
$subtitle.Controls.Add($label)
$selection = New-Object GenshinSubtitleSelectionForm

$cropFrame = New-Object GenshinSubtitleCropForm
$cropFrame.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$cropFrame.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$cropFrame.ShowInTaskbar = $false
$cropFrame.TopMost = $true

$toolbar = New-Object GenshinSubtitleToolbarForm
$toolbar.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$toolbar.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$toolbar.ShowInTaskbar = $false
$toolbar.TopMost = $true
$toolbar.BackColor = [Drawing.Color]::FromArgb(245, 245, 245)
$toolbar.Width = 360
$toolbar.Height = 42
$btnToggle = New-Object System.Windows.Forms.Button
$btnToggle.Location = New-Object Drawing.Point(24, 4)
$btnToggle.Size = New-Object Drawing.Size(68, 30)
$btnLang = New-Object System.Windows.Forms.Button
$btnLang.Location = New-Object Drawing.Point(98, 4)
$btnLang.Size = New-Object Drawing.Size(68, 30)
$btnSettings = New-Object System.Windows.Forms.Button
$btnSettings.Location = New-Object Drawing.Point(172, 4)
$btnSettings.Size = New-Object Drawing.Size(68, 30)
$btnExit = New-Object System.Windows.Forms.Button
$btnExit.Location = New-Object Drawing.Point(246, 4)
$btnExit.Size = New-Object Drawing.Size(68, 30)
[void]$toolbar.Controls.Add($btnToggle)
[void]$toolbar.Controls.Add($btnLang)
[void]$toolbar.Controls.Add($btnSettings)
[void]$toolbar.Controls.Add($btnExit)
$btnHide = New-Object System.Windows.Forms.Button
$btnHide.Location = [Drawing.Point]::new(320, 4)
$btnHide.Size = [Drawing.Size]::new(32, 30)
$btnHide.Font = [Drawing.Font]::new('Marlett', 12)
$btnHide.Text = '0'
[void]$toolbar.Controls.Add($btnHide)
$toolbarTips = New-Object System.Windows.Forms.ToolTip

function Save-ToolbarPosition {
    $bounds = $toolbar.MovementBounds
    $config.ToolbarLeft = [Math]::Round(($toolbar.Left - $bounds.Left) * 100.0 / [Math]::Max(1, $bounds.Width), 2)
    $config.ToolbarTop = [Math]::Round(($toolbar.Top - $bounds.Top) * 100.0 / [Math]::Max(1, $bounds.Height), 2)
    Save-OverlaySettings
}
function Set-ToolbarCollapsed([bool]$Collapsed, [bool]$Persist = $true) {
    $config.ToolbarCollapsed = $Collapsed
    $toolbar.Collapsed = $Collapsed
    foreach ($button in @($btnToggle, $btnLang, $btnSettings, $btnExit, $btnHide)) { $button.Visible = !$Collapsed }
    $toolbar.Size = if ($Collapsed) { [Drawing.Size]::new(40, 40) } else { [Drawing.Size]::new(360, 42) }
    $toolbarTips.SetToolTip($toolbar, $(if ($Collapsed) { Get-UiText 'ShowToolbar' } else { Get-UiText 'DragToolbar' }))
    if ($state.LastBounds) { Update-Layout $state.LastBounds }
    $toolbar.Invalidate()
    if ($Persist) { Save-ToolbarPosition }
}
$btnHide.Add_Click({ Set-ToolbarCollapsed $true })
$toolbar.Add_RestoreRequested({ Set-ToolbarCollapsed $false })
$toolbar.Add_DragCompleted({ Save-ToolbarPosition })

function Update-Buttons {
    $btnToggle.Text = if ($config.PluginLanguage -eq 'ZH') { if ($state.Enabled) { '开' } else { '关' } } else { if ($state.Enabled) { 'ON' } else { 'OFF' } }
    $btnLang.Text = if ($state.Language -eq 'EN') { 'EN' } else { 'ZH' }
    $btnSettings.Text = Get-UiText 'Settings'
    $btnExit.Text = Get-UiText 'Exit'
}
function Get-SubtitleTextHeight([string]$Text, [int]$ContentWidth, [int]$ContentHeight) {
    if (!$Text) {
        if ($label.Font.Size -ne $config.FontSize) {
            $previousFont = $label.Font
            $label.Font = [Drawing.Font]::new('Microsoft YaHei UI', [single]$config.FontSize, [Drawing.FontStyle]::Bold)
            $previousFont.Dispose()
        }
        $state.LayoutKey = ''
        $state.MeasuredHeight = 0
        return 0
    }
    $key = $Text + '|' + $ContentWidth + '|' + $ContentHeight + '|' + $config.FontSize
    if ($state.LayoutKey -eq $key) { return [int]$state.MeasuredHeight }
    $flags = [System.Windows.Forms.TextFormatFlags]::WordBreak -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix -bor [System.Windows.Forms.TextFormatFlags]::NoPadding
    $selectedFont = $null
    $measured = $null
    for ($size = [int]$config.FontSize; $size -ge 8; $size--) {
        $candidate = [Drawing.Font]::new('Microsoft YaHei UI', [single]$size, [Drawing.FontStyle]::Bold)
        $candidateSize = [System.Windows.Forms.TextRenderer]::MeasureText($Text, $candidate, [Drawing.Size]::new($ContentWidth, 10000), $flags)
        if ($candidateSize.Height -le $ContentHeight -and $candidateSize.Width -le $ContentWidth) {
            $selectedFont = $candidate
            $measured = $candidateSize
            break
        }
        $candidate.Dispose()
    }
    if (!$selectedFont) {
        $selectedFont = [Drawing.Font]::new('Microsoft YaHei UI', [single]8, [Drawing.FontStyle]::Bold)
        $measured = [System.Windows.Forms.TextRenderer]::MeasureText($Text, $selectedFont, [Drawing.Size]::new($ContentWidth, 10000), $flags)
    }
    if ($label.Font.Size -ne $selectedFont.Size) {
        $previousFont = $label.Font
        $label.Font = $selectedFont
        $previousFont.Dispose()
    } else {
        $selectedFont.Dispose()
    }
    $state.LayoutKey = $key
    $state.MeasuredHeight = $measured.Height
    return [int]$measured.Height
}
function Update-Layout([object]$Bounds) {
    $left = [int](@($Bounds.Left)[0])
    $top = [int](@($Bounds.Top)[0])
    $right = [int](@($Bounds.Right)[0])
    $bottom = [int](@($Bounds.Bottom)[0])
    $width = $right - $left
    $height = $bottom - $top
    $crop = Get-CropRectangle $Bounds
    $cropFrame.MovementBounds = [Drawing.Rectangle]::FromLTRB($left, $top, $right, $bottom)
    if (!$cropFrame.IsDragging) { $cropFrame.Bounds = $crop }
    $cropFrame.Visible = [bool]($settingsForm.Visible -and $config.ShowFrame)
    $subtitleW = [Math]::Min($width, [Math]::Max(128, [int]($width * $config.DisplayWidth / 100)))
    $subtitleX = $left + [int]($width * $config.DisplayLeft / 100)
    $maxSubtitleH = [Math]::Min($height, [Math]::Max(64, [int]($height * $config.DisplayHeight / 100)))
    $contentWidth = [Math]::Max(20, $subtitleW - 2 * $config.TextPadding - 8)
    $contentHeight = [Math]::Max(20, $maxSubtitleH - 2 * $config.TextPadding - 8)
    $label.Padding = New-Object System.Windows.Forms.Padding($config.TextPadding)
    $measuredHeight = Get-SubtitleTextHeight $label.Text $contentWidth $contentHeight
    $subtitleH = $maxSubtitleH
    $subtitleY = $top + [int]($height * $config.DisplayTop / 100)
    $subtitleX = [Math]::Max($left, [Math]::Min($right - $subtitleW, $subtitleX))
    $subtitleY = [Math]::Max($top, [Math]::Min($bottom - $subtitleH, $subtitleY))
    $subtitle.Bounds = [Drawing.Rectangle]::new($subtitleX, $subtitleY, $subtitleW, $subtitleH)
    $selection.MovementBounds = [Drawing.Rectangle]::FromLTRB($left, $top, $right, $bottom)
    if (!$selection.IsDragging) { $selection.Bounds = $subtitle.Bounds }
    $toolbar.MovementBounds = [Drawing.Rectangle]::FromLTRB($left, $top, $right, $bottom)
    if (!$toolbar.IsDragging) {
        $toolbarX = if ($config.ToolbarLeft -ge 0) { $left + [int]($width * $config.ToolbarLeft / 100) } else { $right - $toolbar.Width - 18 }
        $toolbarY = if ($config.ToolbarTop -ge 0) { $top + [int]($height * $config.ToolbarTop / 100) } else { $bottom - $toolbar.Height - 70 }
        $toolbarX = [Math]::Max($left, [Math]::Min($right - $toolbar.Width, $toolbarX))
        $toolbarY = [Math]::Max($top, [Math]::Min($bottom - $toolbar.Height, $toolbarY))
        $toolbar.Location = [Drawing.Point]::new($toolbarX, $toolbarY)
    }
}
function Set-Subtitle([string]$Text) {
    if ($Text -and $state.Enabled) {
        $label.Text = $Text
        if ($state.LastBounds) { Update-Layout $state.LastBounds }
        $subtitle.Visible = $true
    } else {
        $subtitle.Visible = $false
    }
}
function Get-CurrentSubtitleText {
    if ($state.Language -eq $config.RecognitionLanguage) { return $state.LastSource }
    return $state.LastOpposite
}
function Set-SubtitleLanguage([string]$Language, [bool]$Persist = $true) {
    if ($Language -notin @('ZH', 'EN')) { return }
    $state.Language = $Language
    $config.SubtitleLanguage = $Language
    if ($null -ne $settingSubtitleLanguage) {
        $script:settingsReady = $false
        try { $settingSubtitleLanguage.SelectedIndex = if ($Language -eq 'EN') { 1 } else { 0 } }
        finally { $script:settingsReady = $true }
    }
    if ($Persist) { Save-OverlaySettings }
    Update-Buttons
    if ($state.LastSource -or $state.LastOpposite) { Set-Subtitle (Get-CurrentSubtitleText) }
}
function Switch-SubtitleLanguage {
    Set-SubtitleLanguage $(if ($state.Language -eq 'EN') { 'ZH' } else { 'EN' })
}

$settingsForm = New-Object System.Windows.Forms.Form
$settingsForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$settingsForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$settingsForm.ClientSize = [Drawing.Size]::new(500, 650)
$settingsForm.ShowInTaskbar = $false
$settingsForm.TopMost = $true
$settingsForm.MaximizeBox = $false
$settingsForm.MinimizeBox = $false
$settingsForm.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$settingsForm.Location = [Drawing.Point]::new([System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Left + 20, [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Top + 20)
$settingsTabs = New-Object System.Windows.Forms.TabControl
$settingsTabs.Location = [Drawing.Point]::new(8, 8)
$settingsTabs.Size = [Drawing.Size]::new(484, 590)
$ocrTab = New-Object System.Windows.Forms.TabPage
$displayTab = New-Object System.Windows.Forms.TabPage
[void]$settingsTabs.TabPages.Add($ocrTab)
[void]$settingsTabs.TabPages.Add($displayTab)
[void]$settingsForm.Controls.Add($settingsTabs)

function Add-NumberSetting([System.Windows.Forms.Control]$Parent, [string]$Caption, [double]$Value, [int]$Min, [double]$Max, [int]$RowY, [bool]$Decimal = $false) {
    $captionLabel = New-Object System.Windows.Forms.Label
    $captionLabel.Text = $Caption
    $captionLabel.Location = [Drawing.Point]::new(18, $RowY + 4)
    $captionLabel.Size = [Drawing.Size]::new(245, 24)
    [void]$Parent.Controls.Add($captionLabel)
    $input = New-Object System.Windows.Forms.NumericUpDown
    $input.Minimum = $Min
    $input.Maximum = $Max
    if ($Decimal) { $input.DecimalPlaces = 2; $input.Increment = 0.1 }
    $input.Value = $Value
    $input.Location = [Drawing.Point]::new(370, $RowY)
    $input.Size = [Drawing.Size]::new(85, 26)
    $input.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Right
    $input.Tag = $captionLabel
    [void]$Parent.Controls.Add($input)
    return $input
}
function Add-LanguageSetting([System.Windows.Forms.Control]$Parent, [string]$Caption, [string]$Value, [int]$RowY) {
    $captionLabel = New-Object System.Windows.Forms.Label
    $captionLabel.Text = $Caption
    $captionLabel.Location = [Drawing.Point]::new(18, $RowY + 4)
    $captionLabel.Size = [Drawing.Size]::new(300, 24)
    [void]$Parent.Controls.Add($captionLabel)
    $input = New-Object System.Windows.Forms.ComboBox
    $input.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $input.Location = [Drawing.Point]::new(330, $RowY)
    $input.Size = [Drawing.Size]::new(125, 26)
    [void]$input.Items.AddRange(@((Get-UiText 'Chinese'), (Get-UiText 'English')))
    $input.SelectedIndex = if ($Value -eq 'EN') { 1 } else { 0 }
    $input.Tag = $captionLabel
    [void]$Parent.Controls.Add($input)
    return $input
}

$settingLeft = Add-NumberSetting $ocrTab (Get-UiText 'OcrLeft') $config.Left 0 95 16 $true
$settingTop = Add-NumberSetting $ocrTab (Get-UiText 'OcrTop') $config.Top 0 95 51 $true
$settingWidth = Add-NumberSetting $ocrTab (Get-UiText 'OcrWidth') $config.Width 5 (100 - $config.Left) 86 $true
$settingHeight = Add-NumberSetting $ocrTab (Get-UiText 'OcrHeight') $config.Height 5 (100 - $config.Top) 121 $true
$settingPluginLanguage = Add-LanguageSetting $ocrTab (Get-UiText 'PluginLanguage') $config.PluginLanguage 156
$settingRecognitionLanguage = Add-LanguageSetting $ocrTab (Get-UiText 'RecognitionLanguage') $config.RecognitionLanguage 191
$settingSubtitleLanguage = Add-LanguageSetting $ocrTab (Get-UiText 'SubtitleLanguage') $config.SubtitleLanguage 226
$settingFont = Add-NumberSetting $displayTab (Get-UiText 'MaxFontSize') $config.FontSize 12 48 20
$settingDisplayLeft = Add-NumberSetting $displayTab (Get-UiText 'SubtitleLeft') $config.DisplayLeft 0 95 65 $true
$settingDisplayTop = Add-NumberSetting $displayTab (Get-UiText 'SubtitleTop') $config.DisplayTop 0 95 110 $true
$settingDisplayWidth = Add-NumberSetting $displayTab (Get-UiText 'SubtitleWidth') $config.DisplayWidth 5 (100 - $config.DisplayLeft) 155 $true
$settingDisplayHeight = Add-NumberSetting $displayTab (Get-UiText 'SubtitleHeight') $config.DisplayHeight 5 100 200 $true
$settingTextPadding = Add-NumberSetting $displayTab (Get-UiText 'TextPadding') $config.TextPadding 0 40 245
$dragHint = New-Object System.Windows.Forms.Label
$dragHint.Location = [Drawing.Point]::new(18, 300)
$dragHint.Size = [Drawing.Size]::new(430, 80)
[void]$displayTab.Controls.Add($dragHint)
$settingFrame = New-Object System.Windows.Forms.CheckBox
$settingFrame.Checked = $config.ShowFrame
$settingFrame.Location = [Drawing.Point]::new(18, 264)
$settingFrame.Size = [Drawing.Size]::new(445, 25)
[void]$ocrTab.Controls.Add($settingFrame)
$ocrStatus = New-Object System.Windows.Forms.TextBox
$ocrStatus.ReadOnly = $true
$ocrStatus.Multiline = $true
$ocrStatus.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$ocrStatus.Location = [Drawing.Point]::new(18, 296)
$ocrStatus.Size = [Drawing.Size]::new(445, 72)
[void]$ocrTab.Controls.Add($ocrStatus)
$previewButton = New-Object System.Windows.Forms.Button
$previewButton.Location = [Drawing.Point]::new(18, 376)
$previewButton.Size = [Drawing.Size]::new(220, 30)
[void]$ocrTab.Controls.Add($previewButton)
$previewImage = New-Object System.Windows.Forms.PictureBox
$previewImage.Location = [Drawing.Point]::new(18, 414)
$previewImage.Size = [Drawing.Size]::new(445, 145)
$previewImage.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$previewImage.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
[void]$ocrTab.Controls.Add($previewImage)
$resetSettings = New-Object System.Windows.Forms.Button
$resetSettings.Location = [Drawing.Point]::new(310, 610)
$resetSettings.Size = [Drawing.Size]::new(82, 30)
[void]$settingsForm.Controls.Add($resetSettings)
$closeSettings = New-Object System.Windows.Forms.Button
$closeSettings.Location = [Drawing.Point]::new(402, 610)
$closeSettings.Size = [Drawing.Size]::new(82, 30)
[void]$settingsForm.Controls.Add($closeSettings)

function Set-ComboLanguageItems([System.Windows.Forms.ComboBox]$Combo) {
    $selected = $Combo.SelectedIndex
    $Combo.Items.Clear()
    [void]$Combo.Items.AddRange(@((Get-UiText 'Chinese'), (Get-UiText 'English')))
    $Combo.SelectedIndex = $selected
}
function Apply-UiLanguage {
    $settingsForm.Text = Get-UiText 'SettingsTitle'
    $ocrTab.Text = Get-UiText 'OcrTab'; $displayTab.Text = Get-UiText 'SubtitleTab'
    $settingLeft.Tag.Text = Get-UiText 'OcrLeft'; $settingTop.Tag.Text = Get-UiText 'OcrTop'
    $settingWidth.Tag.Text = Get-UiText 'OcrWidth'; $settingHeight.Tag.Text = Get-UiText 'OcrHeight'
    $settingPluginLanguage.Tag.Text = Get-UiText 'PluginLanguage'
    $settingRecognitionLanguage.Tag.Text = Get-UiText 'RecognitionLanguage'
    $settingSubtitleLanguage.Tag.Text = Get-UiText 'SubtitleLanguage'
    $settingFont.Tag.Text = Get-UiText 'MaxFontSize'; $settingDisplayLeft.Tag.Text = Get-UiText 'SubtitleLeft'
    $settingDisplayTop.Tag.Text = Get-UiText 'SubtitleTop'; $settingDisplayWidth.Tag.Text = Get-UiText 'SubtitleWidth'
    $settingDisplayHeight.Tag.Text = Get-UiText 'SubtitleHeight'; $settingTextPadding.Tag.Text = Get-UiText 'TextPadding'
    $script:settingsReady = $false
    try {
        Set-ComboLanguageItems $settingPluginLanguage
        Set-ComboLanguageItems $settingRecognitionLanguage
        Set-ComboLanguageItems $settingSubtitleLanguage
    } finally { $script:settingsReady = $true }
    $dragHint.Text = Get-UiText 'DragHint'; $settingFrame.Text = Get-UiText 'ShowOcrSelection'
    if (!$state.LastOcr) { $ocrStatus.Text = Get-UiText 'OcrIdle' }
    $previewButton.Text = Get-UiText 'PreviewOcr'; $resetSettings.Text = Get-UiText 'Reset'; $closeSettings.Text = Get-UiText 'Close'
    $toolbarTips.SetToolTip($btnHide, (Get-UiText 'HideToolbar'))
    $toolbarTips.SetToolTip($toolbar, $(if ($toolbar.Collapsed) { Get-UiText 'ShowToolbar' } else { Get-UiText 'DragToolbar' }))
    Update-Buttons
}

$script:settingsReady = $true
Apply-UiLanguage
function Apply-Settings {
    if (!$script:settingsReady) { return }
    $script:settingsReady = $false
    $settingWidth.Maximum = 100 - $settingLeft.Value
    $settingHeight.Maximum = 100 - $settingTop.Value
    $settingDisplayWidth.Maximum = 100 - $settingDisplayLeft.Value
    $script:settingsReady = $true
    $config.Left = [double]$settingLeft.Value
    $config.Top = [double]$settingTop.Value
    $config.Width = [double]$settingWidth.Value
    $config.Height = [double]$settingHeight.Value
    $config.FontSize = [int]$settingFont.Value
    $config.ShowFrame = $settingFrame.Checked
    $selectedPluginLanguage = if ($settingPluginLanguage.SelectedIndex -eq 1) { 'EN' } else { 'ZH' }
    if ($config.PluginLanguage -ne $selectedPluginLanguage) {
        $config.PluginLanguage = $selectedPluginLanguage
        Apply-UiLanguage
    }
    $selectedRecognitionLanguage = if ($settingRecognitionLanguage.SelectedIndex -eq 1) { 'EN' } else { 'ZH' }
    if ($config.RecognitionLanguage -ne $selectedRecognitionLanguage) {
        $config.RecognitionLanguage = $selectedRecognitionLanguage
        $state.LastOcr = ''; $state.LastLookup = ''; $state.LastSource = ''; $state.LastOpposite = ''; $state.Misses = 0
        Set-Subtitle ''
    }
    $selectedSubtitleLanguage = if ($settingSubtitleLanguage.SelectedIndex -eq 1) { 'EN' } else { 'ZH' }
    if ($state.Language -ne $selectedSubtitleLanguage) { Set-SubtitleLanguage $selectedSubtitleLanguage $false }
    $config.DisplayLeft = [double]$settingDisplayLeft.Value
    $config.DisplayTop = [double]$settingDisplayTop.Value
    $config.DisplayWidth = [double]$settingDisplayWidth.Value
    $config.DisplayHeight = [double]$settingDisplayHeight.Value
    $config.TextPadding = [int]$settingTextPadding.Value
    Save-OverlaySettings
    if ($state.LastBounds) { Update-Layout $state.LastBounds }
}
foreach ($input in @($settingLeft, $settingTop, $settingWidth, $settingHeight, $settingFont, $settingDisplayLeft, $settingDisplayTop, $settingDisplayWidth, $settingDisplayHeight, $settingTextPadding)) {
    $input.Add_ValueChanged({ Apply-Settings })
}
$settingFrame.Add_CheckedChanged({ Apply-Settings })
$settingPluginLanguage.Add_SelectedIndexChanged({ Apply-Settings })
$settingRecognitionLanguage.Add_SelectedIndexChanged({ Apply-Settings })
$settingSubtitleLanguage.Add_SelectedIndexChanged({ Apply-Settings })
$resetSettings.Add_Click({
    $script:settingsReady = $false
    $settingLeft.Value = 16.5; $settingTop.Value = 84
    $settingWidth.Maximum = 100; $settingHeight.Maximum = 100; $settingDisplayWidth.Maximum = 100
    $settingWidth.Value = 67; $settingHeight.Value = 9.5
    $settingFont.Value = 24; $settingFrame.Checked = $true
    $settingPluginLanguage.SelectedIndex = 0
    $settingRecognitionLanguage.SelectedIndex = 1
    $settingSubtitleLanguage.SelectedIndex = 1
    $settingDisplayLeft.Value = 16.5; $settingDisplayTop.Value = 93.5; $settingDisplayWidth.Value = 67
    $settingDisplayHeight.Value = 5.5; $settingTextPadding.Value = 16
    $script:settingsReady = $true
    Apply-Settings
})
$closeSettings.Add_Click({ $settingsForm.Hide() })
$settingsForm.Add_FormClosing({ param($sender, $eventArgs) $eventArgs.Cancel = $true; $settingsForm.Hide() })

function Sync-SubtitleSelection([bool]$Persist = $false) {
    if (!$state.LastBounds) { return }
    $bounds = $state.LastBounds
    $gameLeft = [int](@($bounds.Left)[0]); $gameTop = [int](@($bounds.Top)[0])
    $gameWidth = [Math]::Max(1, [int](@($bounds.Right)[0]) - $gameLeft)
    $gameHeight = [Math]::Max(1, [int](@($bounds.Bottom)[0]) - $gameTop)
    $displayLeft = [Math]::Round((($selection.Left - $gameLeft) * 100.0) / $gameWidth, 2)
    $displayTop = [Math]::Round((($selection.Top - $gameTop) * 100.0) / $gameHeight, 2)
    $config.DisplayLeft = [Math]::Max(0.0, [Math]::Min(95.0, $displayLeft))
    $config.DisplayTop = [Math]::Max(0.0, [Math]::Min(95.0, $displayTop))
    $config.DisplayWidth = [Math]::Max(5.0, [Math]::Min(100.0 - $config.DisplayLeft, [Math]::Round($selection.Width * 100.0 / $gameWidth, 2)))
    $config.DisplayHeight = [Math]::Max(5.0, [Math]::Min(100.0, [Math]::Round($selection.Height * 100.0 / $gameHeight, 2)))
    $script:settingsReady = $false
    try {
        $settingDisplayLeft.Value = $config.DisplayLeft
        $settingDisplayTop.Value = $config.DisplayTop
        $settingDisplayWidth.Maximum = 100 - $settingDisplayLeft.Value
        $settingDisplayWidth.Value = $config.DisplayWidth
        $settingDisplayHeight.Value = $config.DisplayHeight
    }
    finally { $script:settingsReady = $true }
    if ($Persist) { Save-OverlaySettings }
    Update-Layout $state.LastBounds
}

function Sync-CropSelection([bool]$Persist = $false) {
    if (!$state.LastBounds) { return }
    $bounds = $state.LastBounds
    $gameLeft = [int](@($bounds.Left)[0]); $gameTop = [int](@($bounds.Top)[0])
    $gameWidth = [Math]::Max(1, [int](@($bounds.Right)[0]) - $gameLeft)
    $gameHeight = [Math]::Max(1, [int](@($bounds.Bottom)[0]) - $gameTop)
    $displayLeft = [Math]::Round((($cropFrame.Left - $gameLeft) * 100.0) / $gameWidth, 2)
    $displayTop = [Math]::Round((($cropFrame.Top - $gameTop) * 100.0) / $gameHeight, 2)
    $config.Left = [Math]::Max(0.0, [Math]::Min(95.0, $displayLeft))
    $config.Top = [Math]::Max(0.0, [Math]::Min(95.0, $displayTop))
    $config.Width = [Math]::Max(5.0, [Math]::Min(100.0 - $config.Left, [Math]::Round($cropFrame.Width * 100.0 / $gameWidth, 2)))
    $config.Height = [Math]::Max(5.0, [Math]::Min(100.0 - $config.Top, [Math]::Round($cropFrame.Height * 100.0 / $gameHeight, 2)))
    $script:settingsReady = $false
    try {
        $settingLeft.Value = $config.Left
        $settingTop.Value = $config.Top
        $settingWidth.Maximum = 100 - $settingLeft.Value
        $settingWidth.Value = $config.Width
        $settingHeight.Maximum = 100 - $settingTop.Value
        $settingHeight.Value = $config.Height
    }
    finally { $script:settingsReady = $true }
    if ($Persist) { Save-OverlaySettings }
    Update-Layout $state.LastBounds
}

$cropFrame.Add_BoundsEdited({ if ($settingsForm.Visible) { Sync-CropSelection } })
$cropFrame.Add_EditCompleted({ if ($settingsForm.Visible) { Sync-CropSelection $true } })
$selection.Add_BoundsEdited({ if ($settingsForm.Visible) { Sync-SubtitleSelection } })
$selection.Add_EditCompleted({ if ($settingsForm.Visible) { Sync-SubtitleSelection $true } })
$settingsForm.Add_VisibleChanged({
    if ($settingsForm.Visible) {
        if (!$subtitle.Visible) {
            $state.SettingsPreview = $true
            $state.SettingsPreviousText = $label.Text
            $state.SettingsPreviousVisible = $subtitle.Visible
            $label.Text = Get-UiText 'DragSubtitle'
            if ($state.LastBounds) { Update-Layout $state.LastBounds }
            $subtitle.Visible = $true
        } elseif ($state.LastBounds) {
            Update-Layout $state.LastBounds
        }
        $selection.Show()
        $selection.BringToFront()
        $settingsForm.BringToFront()
    } else {
        $selection.Hide()
        $cropFrame.Visible = $false
        if ($state.SettingsPreview) {
            $label.Text = $state.SettingsPreviousText
            $subtitle.Visible = [bool]$state.SettingsPreviousVisible
            $state.SettingsPreview = $false
        }
    }
})
$previewButton.Add_Click({
    try {
        if ($state.LastBounds) { Update-Layout $state.LastBounds }
        $settingsForm.Hide()
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 150
        Capture-SubtitleRegion (Get-CropFrameScreenBounds) $tempImage
        $loaded = [Drawing.Image]::FromFile($tempImage)
        try { $snapshot = [Drawing.Bitmap]::new($loaded) } finally { $loaded.Dispose() }
        $oldImage = $previewImage.Image
        $previewImage.Image = $snapshot
        if ($oldImage) { $oldImage.Dispose() }
        $ocrStatus.Text = (Get-UiText 'PreviewInput') + ' (' + $snapshot.Width + ' x ' + $snapshot.Height + ' px)'
    }
    catch { $ocrStatus.Text = (Get-UiText 'PreviewError') + ': ' + $_.Exception.Message }
    finally { $settingsForm.Show(); $settingsForm.Activate() }
})

$btnToggle.Add_Click({ $state.Enabled = !$state.Enabled; Update-Buttons; if (!$state.Enabled) { Set-Subtitle '' } })
$btnLang.Add_Click({ Switch-SubtitleLanguage })
$btnSettings.Add_Click({ $settingsForm.Show(); $settingsForm.BringToFront(); $settingsForm.Activate() })
$btnExit.Add_Click({ $toolbar.Close() })
$toolbar.Add_FormClosed({ $selection.Dispose(); [System.Windows.Forms.Application]::ExitThread() })

$subtitle.Add_Shown({ [GenshinSubtitleOverlayNative]::MakeNoActivate($subtitle.Handle) })
$toolbar.Add_Shown({ Update-Buttons })
$subtitle.Visible = $false
$initialBounds = @(Get-GameBounds | Select-Object -Last 1)[0]
$state.LastBounds = $initialBounds
Set-ToolbarCollapsed ([bool]$config.ToolbarCollapsed) $false
Update-Layout $initialBounds
Update-Buttons
$toolbar.Show()
[GenshinSubtitleOverlayNative]::MakeNoActivate($subtitle.Handle)

if ($UiCheck) {
    if (!$settingsExistedAtStartup -and !$freshDefaultsApplied) { throw ('Fresh-start defaults do not match the requested layout and languages: ' + ($config | ConvertTo-Json -Compress)) }
    function Send-ToolbarMouse([int]$Message, [int]$X, [int]$Y) {
        $packed = ($X -band 0xffff) -bor (($Y -band 0xffff) -shl 16)
        [void][GenshinSubtitleOverlayNative]::SendMessage($toolbar.Handle, $Message, [IntPtr]::new(1), [IntPtr]::new($packed))
    }
    Set-ToolbarCollapsed $false $false
    $toolbar.Location = [Drawing.Point]::new($toolbar.MovementBounds.Left + 700, $toolbar.MovementBounds.Top + 700)
    Save-ToolbarPosition
    $beforeToolbar = $toolbar.Location
    Send-ToolbarMouse 0x201 10 20
    Send-ToolbarMouse 0x200 70 50
    Send-ToolbarMouse 0x202 10 20
    Update-Layout $state.LastBounds
    if ([Math]::Abs($toolbar.Left - $beforeToolbar.X - 60) -gt 1 -or [Math]::Abs($toolbar.Top - $beforeToolbar.Y - 30) -gt 1) {
        throw 'Toolbar drag or retained position failed.'
    }
    $btnHide.PerformClick()
    if (!$toolbar.Collapsed -or $toolbar.Width -ne 40 -or $btnToggle.Visible) { throw 'Toolbar did not collapse to an icon.' }
    $beforeToolbar = $toolbar.Location
    Send-ToolbarMouse 0x201 20 20
    Send-ToolbarMouse 0x200 50 40
    Send-ToolbarMouse 0x202 20 20
    Update-Layout $state.LastBounds
    if (!$toolbar.Collapsed -or [Math]::Abs($toolbar.Left - $beforeToolbar.X - 30) -gt 1 -or [Math]::Abs($toolbar.Top - $beforeToolbar.Y - 20) -gt 1) {
        throw 'Collapsed icon drag unexpectedly restored the toolbar or lost position.'
    }
    $toolbarSnapshot = [Drawing.Bitmap]::new($toolbar.Width, $toolbar.Height)
    try {
        $toolbar.DrawToBitmap($toolbarSnapshot, [Drawing.Rectangle]::new(0, 0, $toolbar.Width, $toolbar.Height))
        $toolbarSnapshot.Save((Join-Path $root 'test-results/toolbar-icon-check.png'), [Drawing.Imaging.ImageFormat]::Png)
    } finally { $toolbarSnapshot.Dispose() }
    $savedToolbar = Get-Content -Raw -LiteralPath (Join-Path $root 'test-results/overlay-ui-settings.json') | ConvertFrom-Json
    if (!$savedToolbar.ToolbarCollapsed -or $savedToolbar.ToolbarLeft -ne $config.ToolbarLeft -or $savedToolbar.ToolbarTop -ne $config.ToolbarTop) {
        throw 'Toolbar collapsed state and position were not saved.'
    }
    Send-ToolbarMouse 0x201 20 20
    Send-ToolbarMouse 0x202 20 20
    if ($toolbar.Collapsed -or !$btnToggle.Visible -or $toolbar.Width -ne 360) { throw 'Icon click did not restore the toolbar.' }
    $toolbarSnapshot = [Drawing.Bitmap]::new($toolbar.Width, $toolbar.Height)
    try {
        $toolbar.DrawToBitmap($toolbarSnapshot, [Drawing.Rectangle]::new(0, 0, $toolbar.Width, $toolbar.Height))
        $toolbarSnapshot.Save((Join-Path $root 'test-results/toolbar-layout-check.png'), [Drawing.Imaging.ImageFormat]::Png)
    } finally { $toolbarSnapshot.Dispose() }
    $frameHiddenOutsideSettings = !$cropFrame.Visible
    $transparentSubtitle = $subtitle.Opacity -eq 1.0 -and $subtitle.TransparencyKey.ToArgb() -eq [Drawing.Color]::Magenta.ToArgb()
    $settingsForm.Show()
    [System.Windows.Forms.Application]::DoEvents()
    $frameVisibleInSettings = $cropFrame.Visible
    $dragEnabledInSettings = $selection.Visible -and $selection.TransparencyKey.IsEmpty -and $selection.Controls.Count -eq 0
    function Send-SelectionMouse([int]$Message, [int]$X, [int]$Y) {
        $packed = ($X -band 0xffff) -bor (($Y -band 0xffff) -shl 16)
        [void][GenshinSubtitleOverlayNative]::SendMessage($selection.Handle, $Message, [IntPtr]::new(1), [IntPtr]::new($packed))
    }
    $testLeft = $selection.MovementBounds.Left + 550
    $testTop = $selection.MovementBounds.Top + 250
    $selection.Bounds = [Drawing.Rectangle]::new($testLeft, $testTop, 600, 240)
    Sync-SubtitleSelection
    $before = $selection.Bounds
    $hitPoint = [Drawing.Point]::new($selection.Left + 100, $selection.Top + 80)
    if ([GenshinSubtitleOverlayNative]::WindowFromPoint($hitPoint) -ne $selection.Handle) {
        throw 'The selection interior is not receiving desktop mouse hit tests.'
    }
    Send-SelectionMouse 0x201 100 80
    Send-SelectionMouse 0x200 140 110
    Send-SelectionMouse 0x202 100 80
    if ([Math]::Abs($selection.Left - $before.Left - 40) -gt 1 -or [Math]::Abs($selection.Top - $before.Top - 30) -gt 1) {
        throw ('Mouse messages did not move the selection: ' + $before.ToString() + ' -> ' + $selection.Bounds.ToString())
    }
    # Exercise all four edges and four corners through the actual window mouse events.
    foreach ($edge in @(1, 2, 4, 8, 5, 6, 9, 10)) {
        $selection.Bounds = [Drawing.Rectangle]::new($testLeft, $testTop, 600, 240)
        Sync-SubtitleSelection
        $before = $selection.Bounds
        $x = if ($edge -band 1) { 2 } elseif ($edge -band 2) { $selection.Width - 2 } else { 100 }
        $y = if ($edge -band 4) { 2 } elseif ($edge -band 8) { $selection.Height - 2 } else { 80 }
        $dx = if ($edge -band 1) { -30 } elseif ($edge -band 2) { 30 } else { 0 }
        $dy = if ($edge -band 4) { -20 } elseif ($edge -band 8) { 20 } else { 0 }
        Send-SelectionMouse 0x201 $x $y
        Send-SelectionMouse 0x200 ($x + $dx) ($y + $dy)
        Send-SelectionMouse 0x202 $x $y
        $expectedW = $before.Width + [Math]::Abs($dx)
        $expectedH = $before.Height + [Math]::Abs($dy)
        if ([Math]::Abs($selection.Width - $expectedW) -gt 1 -or [Math]::Abs($selection.Height - $expectedH) -gt 1) {
            throw "Selection resize failed for edge $edge."
        }
    }
    $persisted = Get-Content -Raw -LiteralPath (Join-Path $root 'test-results/overlay-ui-settings.json') | ConvertFrom-Json
    $dragPositionSaved = $persisted.DisplayLeft -eq $config.DisplayLeft -and $persisted.DisplayTop -eq $config.DisplayTop -and $persisted.DisplayWidth -eq $config.DisplayWidth -and $persisted.DisplayHeight -eq $config.DisplayHeight
    function Send-CropMouse([int]$Message, [int]$X, [int]$Y) {
        $packed = ($X -band 0xffff) -bor (($Y -band 0xffff) -shl 16)
        [void][GenshinSubtitleOverlayNative]::SendMessage($cropFrame.Handle, $Message, [IntPtr]::new(1), [IntPtr]::new($packed))
    }
    $cropFrame.BringToFront()
    $testLeft = $cropFrame.MovementBounds.Left + 550
    $testTop = $cropFrame.MovementBounds.Top + 250
    $cropFrame.Bounds = [Drawing.Rectangle]::new($testLeft, $testTop, 600, 240)
    Sync-CropSelection
    $before = $cropFrame.Bounds
    $hitPoint = [Drawing.Point]::new($cropFrame.Left + 100, $cropFrame.Top + 80)
    if ([GenshinSubtitleOverlayNative]::WindowFromPoint($hitPoint) -ne $cropFrame.Handle) {
        throw 'The selection interior is not receiving desktop mouse hit tests.'
    }
    Send-CropMouse 0x201 100 80
    Send-CropMouse 0x200 140 110
    Send-CropMouse 0x202 100 80
    if ([Math]::Abs($cropFrame.Left - $before.Left - 40) -gt 1 -or [Math]::Abs($cropFrame.Top - $before.Top - 30) -gt 1) {
        throw ('Mouse messages did not move the selection: ' + $before.ToString() + ' -> ' + $cropFrame.Bounds.ToString())
    }
    # Exercise all four edges and four corners through the actual window mouse events.
    foreach ($edge in @(1, 2, 4, 8, 5, 6, 9, 10)) {
        $cropFrame.Bounds = [Drawing.Rectangle]::new($testLeft, $testTop, 600, 240)
        Sync-CropSelection
        $before = $cropFrame.Bounds
        $x = if ($edge -band 1) { 2 } elseif ($edge -band 2) { $cropFrame.Width - 2 } else { 100 }
        $y = if ($edge -band 4) { 2 } elseif ($edge -band 8) { $cropFrame.Height - 2 } else { 80 }
        $dx = if ($edge -band 1) { -30 } elseif ($edge -band 2) { 30 } else { 0 }
        $dy = if ($edge -band 4) { -20 } elseif ($edge -band 8) { 20 } else { 0 }
        Send-CropMouse 0x201 $x $y
        Send-CropMouse 0x200 ($x + $dx) ($y + $dy)
        Send-CropMouse 0x202 $x $y
        $expectedW = $before.Width + [Math]::Abs($dx)
        $expectedH = $before.Height + [Math]::Abs($dy)
        if ([Math]::Abs($cropFrame.Width - $expectedW) -gt 1 -or [Math]::Abs($cropFrame.Height - $expectedH) -gt 1) {
            throw "Selection resize failed for edge $edge."
        }
    }
    $persisted = Get-Content -Raw -LiteralPath (Join-Path $root 'test-results/overlay-ui-settings.json') | ConvertFrom-Json
    $cropPositionSaved = $persisted.Left -eq $config.Left -and $persisted.Top -eq $config.Top -and $persisted.Width -eq $config.Width -and $persisted.Height -eq $config.Height
    if (!$cropPositionSaved) { throw 'OCR selection position and size were not saved.' }
    $cropSnapshot = [Drawing.Bitmap]::new($cropFrame.Width, $cropFrame.Height)
    try {
        $cropFrame.DrawToBitmap($cropSnapshot, [Drawing.Rectangle]::new(0, 0, $cropFrame.Width, $cropFrame.Height))
        $cropSnapshot.Save((Join-Path $root 'test-results/ocr-selection-check.png'), [Drawing.Imaging.ImageFormat]::Png)
    } finally { $cropSnapshot.Dispose() }
    $settingsForm.Hide()
    [System.Windows.Forms.Application]::DoEvents()
    $frameHiddenAfterSettings = !$cropFrame.Visible
    $dragDisabledAfterSettings = $subtitle.ClickThrough -and !$selection.Visible
    $settingsForm.Show()
    [System.Windows.Forms.Application]::DoEvents()
    if (!$frameHiddenOutsideSettings -or !$frameVisibleInSettings -or !$frameHiddenAfterSettings -or !$dragEnabledInSettings -or !$dragDisabledAfterSettings -or !$dragPositionSaved -or !$transparentSubtitle) {
        throw 'Frame visibility, transparent subtitle style, or settings-only drag behavior is incorrect.'
    }
    $settingDisplayLeft.Value = 5; $settingDisplayWidth.Value = 90
    $settingDisplayHeight.Value = 18
    $settingRecognitionLanguage.SelectedIndex = 0
    $settingSubtitleLanguage.SelectedIndex = 1
    $originalX = $cropFrame.Left
    $settingLeft.Value = [int]$settingLeft.Value + $(if ($settingLeft.Value -lt 95) { 1 } else { -1 })
    $positionChanged = $cropFrame.Left -ne $originalX
    $settingFont.Value = [int]$settingFont.Value + $(if ($settingFont.Value -lt 48) { 1 } else { -1 })
    $fontChanged = $label.Font.Size -eq $settingFont.Value
    $previousSubtitleWidth = $subtitle.Width
    $settingDisplayWidth.Value = [int]$settingDisplayWidth.Value + $(if ($settingDisplayWidth.Value -lt $settingDisplayWidth.Maximum) { 1 } else { -1 })
    $displayWidthChanged = $subtitle.Width -ne $previousSubtitleWidth
    $frameScreenBounds = Get-CropFrameScreenBounds
    $captureBounds = Get-CaptureRectangle $frameScreenBounds
    if (!$positionChanged -or !$fontChanged -or !$displayWidthChanged -or $captureBounds.Left -ne ($frameScreenBounds.Left + 5) -or $captureBounds.Top -ne ($frameScreenBounds.Top + 5)) { throw 'Settings controls or OCR crop bounds are incorrect.' }
    $state.LastOcr = '测试中文字幕超过十个字符'
    $state.LastSource = '官方中文字幕示例。'
    $state.LastOpposite = 'An official English subtitle example.'
    $btnLang.PerformClick()
    $zhWorks = $state.Language -eq 'ZH' -and $label.Text -eq $state.LastSource
    $btnLang.PerformClick()
    $enWorks = $state.Language -eq 'EN' -and $label.Text -eq $state.LastOpposite
    if (!$zhWorks -or !$enWorks) { throw 'Language button did not switch both subtitle texts.' }
    $settingRecognitionLanguage.SelectedIndex = 1
    $recognitionSwitchWorks = $config.RecognitionLanguage -eq 'EN' -and $state.Language -eq 'EN' -and !$state.LastOcr
    if (!$recognitionSwitchWorks) { throw 'OCR recognition language did not switch independently.' }
    $state.LastOcr = 'Observed English subtitle text.'
    $state.LastSource = 'Official English subtitle sample.'
    $state.LastOpposite = '官方中文字幕示例。'
    $btnLang.PerformClick()
    $zhOfficialWorks = $state.Language -eq 'ZH' -and $label.Text -eq $state.LastOpposite
    $btnLang.PerformClick()
    $enOfficialWorks = $state.Language -eq 'EN' -and $label.Text -eq $state.LastSource
    if (!$enOfficialWorks -or !$zhOfficialWorks) { throw 'English recognition language did not switch both official subtitle texts.' }
    $settingPluginLanguage.SelectedIndex = 1
    $englishUiWorks = $config.PluginLanguage -eq 'EN' -and $settingsForm.Text -eq 'Subtitle settings' -and $settingRecognitionLanguage.Items[1] -eq 'English'
    $settingPluginLanguage.SelectedIndex = 0
    $chineseUiWorks = $config.PluginLanguage -eq 'ZH' -and $settingsForm.Text -eq '字幕设置' -and $settingRecognitionLanguage.Items[1] -eq '英文'
    if (!$englishUiWorks -or !$chineseUiWorks) { throw 'Plugin language did not update the interface.' }
    $realLookup = Lookup-Official 'But for now, all yo u need to remember is this: If yo u collect Kresnik KristaII, can extract' 'EN'
    if (!$realLookup.opposite.Contains(([string][char]0x514B + [char]0x4EC0 + [char]0x5C3C + [char]0x514B)) -or !$realLookup.source.StartsWith('But for now')) { throw 'PowerShell English-to-Chinese official lookup failed.' }
    $resetSettings.PerformClick()
    $defaultsWork = $config.Left -eq 16.5 -and $config.Top -eq 84 -and $config.Width -eq 67 -and $config.Height -eq 9.5 -and
        $config.FontSize -eq 24 -and $config.DisplayLeft -eq 16.5 -and $config.DisplayTop -eq 93.5 -and $config.DisplayWidth -eq 67 -and
        $config.DisplayHeight -eq 5.5 -and $config.TextPadding -eq 16 -and $config.PluginLanguage -eq 'ZH' -and
        $config.RecognitionLanguage -eq 'EN' -and $config.SubtitleLanguage -eq 'EN'
    if (!$defaultsWork) { throw 'Reset did not restore the requested layout and language defaults.' }
    $longText = 'But for now, all you need to remember is this: If you collect Kresnik Kristall, I can extract the energy within and keep your body temperature stable. Remember that before we move on.'
    Set-Subtitle $longText
    $contentWidth = $subtitle.Width - 2 * $config.TextPadding
    $contentHeight = $subtitle.Height - 2 * $config.TextPadding
    $flags = [System.Windows.Forms.TextFormatFlags]::WordBreak -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix -bor [System.Windows.Forms.TextFormatFlags]::NoPadding
    $measured = [System.Windows.Forms.TextRenderer]::MeasureText($label.Text, $label.Font, [Drawing.Size]::new($contentWidth, 10000), $flags)
    $longTextFits = !$label.AutoEllipsis -and $label.Text -eq $longText -and $measured.Height -le $contentHeight
    if (!$longTextFits) { throw 'Long subtitle does not fit in the display area.' }
    $subtitleSnapshot = [Drawing.Bitmap]::new($subtitle.Width, $subtitle.Height)
    try {
        $subtitle.DrawToBitmap($subtitleSnapshot, [Drawing.Rectangle]::new(0, 0, $subtitle.Width, $subtitle.Height))
        $subtitleSnapshot.Save((Join-Path $root 'test-results/subtitle-layout-check.png'), [Drawing.Imaging.ImageFormat]::Png)
    } finally { $subtitleSnapshot.Dispose() }
    $settingsTabs.SelectedTab = $displayTab
    $settingsSnapshot = [Drawing.Bitmap]::new($settingsForm.Width, $settingsForm.Height)
    try {
        $settingsForm.DrawToBitmap($settingsSnapshot, [Drawing.Rectangle]::new(0, 0, $settingsForm.Width, $settingsForm.Height))
        $settingsSnapshot.Save((Join-Path $root 'test-results/settings-layout-check.png'), [Drawing.Imaging.ImageFormat]::Png)
    } finally { $settingsSnapshot.Dispose() }
    $settingsTabs.SelectedTab = $ocrTab
    $ocrSettingsSnapshot = [Drawing.Bitmap]::new($settingsForm.Width, $settingsForm.Height)
    try {
        $settingsForm.DrawToBitmap($ocrSettingsSnapshot, [Drawing.Rectangle]::new(0, 0, $settingsForm.Width, $settingsForm.Height))
        $ocrSettingsSnapshot.Save((Join-Path $root 'test-results/ocr-settings-layout-check.png'), [Drawing.Imaging.ImageFormat]::Png)
    } finally { $ocrSettingsSnapshot.Dispose() }
    [pscustomobject]@{
        toolbar_buttons = $toolbar.Controls.Count
        toolbar_drag_collapse_restore = 'ok'
        settings_controls = $settingsForm.Controls.Count
        crop_bounds = $cropFrame.Bounds.ToString()
        frame_screen_bounds = $frameScreenBounds.ToString()
        crop_visible = $cropFrame.Visible
        frame_settings_only = 'ok'
        transparent_subtitle = 'ok'
        drag_position_save = 'ok'
        mouse_move_and_eight_resize_handles = 'ok'
        ocr_move_eight_resize_and_save = 'ok'
        desktop_mouse_hit_test = 'ok'
        font_size = $label.Font.Size
        setting_events = 'ok'
        language_button = 'ok'
        recognition_and_output_language = 'ok'
        plugin_language = 'ok'
        requested_defaults = 'ok'
        fresh_start_defaults = $(if ($settingsExistedAtStartup) { 'not tested: existing settings loaded' } elseif ($freshDefaultsApplied) { 'ok' } else { 'failed' })
        english_to_chinese_lookup = 'ok'
        long_subtitle_fits = $longTextFits
        subtitle_bounds = $subtitle.Bounds.ToString()
        capture_bounds = $captureBounds.ToString()
    } | ConvertTo-Json
    $settingsForm.Dispose()
    $cropFrame.Dispose()
    $subtitle.Dispose()
    $toolbar.Dispose()
    exit 0
}

$hotkeyTimer = New-Object System.Windows.Forms.Timer
$hotkeyTimer.Interval = 45
$hotkeyState = @{ Toggle = $false; Language = $false }
$hotkeyTimer.Add_Tick({
    $ctrl = (([GenshinSubtitleOverlayNative]::GetAsyncKeyState(0x11) -band 0x8000) -ne 0)
    $shift = (([GenshinSubtitleOverlayNative]::GetAsyncKeyState(0x10) -band 0x8000) -ne 0)
    $toggle = $ctrl -and $shift -and (([GenshinSubtitleOverlayNative]::GetAsyncKeyState(0x54) -band 0x8000) -ne 0)
    $language = $ctrl -and $shift -and (([GenshinSubtitleOverlayNative]::GetAsyncKeyState(0x59) -band 0x8000) -ne 0)
    if ($toggle -and !$hotkeyState.Toggle) { $state.Enabled = !$state.Enabled; Update-Buttons; if (!$state.Enabled) { Set-Subtitle '' } }
    if ($language -and !$hotkeyState.Language) { Switch-SubtitleLanguage }
    $hotkeyState.Toggle = $toggle
    $hotkeyState.Language = $language
})

$scanTimer = New-Object System.Windows.Forms.Timer
$scanTimer.Interval = 700
$scanTimer.Add_Tick({
    if ($state.Busy -or $settingsForm.Visible) { return }
    $state.Busy = $true
    try {
        $bounds = @(Get-GameBounds | Select-Object -Last 1)[0]
        $state.LastBounds = $bounds
        Update-Layout $bounds
        Capture-SubtitleRegion (Get-CropFrameScreenBounds) $tempImage
        $activeEngine = if ($config.RecognitionLanguage -eq 'EN') { if ($enEngine) { $enEngine } else { $zhEngine } } else { if ($zhEngine) { $zhEngine } else { $enEngine } }
        $ocrText = (Invoke-Ocr $tempImage $activeEngine).Trim()
        if (!$ocrText -or (Get-VisibleLength $ocrText) -le 10) {
            $ocrStatus.Text = if ($ocrText) { (Get-UiText 'OcrShort') + ': ' + $ocrText } else { Get-UiText 'OcrNoText' }
            $state.Misses++
            # Keep the last result through transient OCR misses. Clear only
            # after several consecutive misses, which prevents visible flicker.
            if ($state.Misses -ge 4) { Set-Subtitle '' }
            return
        }
        $state.Misses = 0
        if ($ocrText -ne $state.LastLookup) {
            $official = Lookup-Official $ocrText $config.RecognitionLanguage
            $state.LastSource = if ($official.source) { $official.source } else { $ocrText }
            $state.LastOpposite = $official.opposite
            $state.LastLookup = $ocrText
        }
        $state.LastOcr = $ocrText
        $oppositeLanguage = if ($config.RecognitionLanguage -eq 'EN') { 'ZH' } else { 'EN' }
        $ocrEngineName = if ($config.RecognitionLanguage -eq 'EN' -and !$enEngine) { 'EN via Chinese OCR' } else { $config.RecognitionLanguage }
        $ocrStatus.Text = 'OCR (' + $ocrEngineName + '): ' + $ocrText + [Environment]::NewLine + (Get-UiText 'Official') + ' ' + (Get-LanguageName $oppositeLanguage) + ': ' + $(if ($state.LastOpposite) { $state.LastOpposite } else { Get-UiText 'NoMatch' })
        Set-Subtitle (Get-CurrentSubtitleText)
    }
    catch {
        $ocrStatus.Text = (Get-UiText 'OcrError') + ': ' + $_.Exception.Message
        try {
            Add-Content -LiteralPath (Join-Path $root 'overlay-errors.log') -Value ((Get-Date -Format o) + ' ' + $_.Exception.ToString())
        } catch {}
        $state.Misses++
        if ($state.Misses -ge 4) { Set-Subtitle '' }
    }
    finally {
        $state.Busy = $false
    }
})
$hotkeyTimer.Start()
$scanTimer.Start()
[System.Windows.Forms.Application]::Run()
$hotkeyTimer.Stop()
$scanTimer.Stop()
if (Test-Path -LiteralPath $tempImage) { Remove-Item -LiteralPath $tempImage -Force -ErrorAction SilentlyContinue }
