function Await-WinRT([object]$Operation, [type]$ResultType) {
    $method = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.IsGenericMethodDefinition -and $_.GetGenericArguments().Count -eq 1 -and $_.GetParameters().Count -eq 1
    } | Select-Object -First 1
    $task = $method.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    return $task.GetAwaiter().GetResult()
}

function Get-CropRectangle([object]$Bounds) {
    $left = [int](@($Bounds.Left)[0]); $top = [int](@($Bounds.Top)[0])
    $width = [Math]::Max(20, [int](@($Bounds.Right)[0]) - $left)
    $height = [Math]::Max(20, [int](@($Bounds.Bottom)[0]) - $top)
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
        if ($softwareBitmap) { try { $softwareBitmap.Dispose() } catch {} }
        if ($stream) { try { $stream.Dispose() } catch {} }
    }
}

function Get-VisibleLength([string]$Text) {
    $compact = [regex]::Replace($Text, '\s+', '')
    if (!$compact) { return 0 }
    return [System.Globalization.StringInfo]::ParseCombiningCharacters($compact).Length
}
