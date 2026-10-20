# Generates the 1024x1024 app icon (opaque PNG) with System.Drawing: a screen with a play button on an
# orange gradient. The automated CarPlay test finds the icon on the car's home screen by its orange.
param([string]$Out = "CarVideo/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
Add-Type -AssemblyName System.Drawing
$size = 1024
$bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

$rect = New-Object System.Drawing.Rectangle 0, 0, $size, $size
$c1 = [System.Drawing.Color]::FromArgb(255, 255, 179, 0)
$c2 = [System.Drawing.Color]::FromArgb(255, 255, 84, 20)
$bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, $c1, $c2, 45.0
$g.FillRectangle($bg, $rect)

function RoundedRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = 2 * $r
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

# Soft shadow under the screen
$shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(45, 120, 30, 0))
$g.FillPath($shadow, (RoundedRect 182 262 680 440 70))

# The screen: white panel with an orange play triangle
$white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
$g.FillPath($white, (RoundedRect 172 240 680 440 70))
$play = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 110, 20))
$tri = @(
    (New-Object System.Drawing.PointF 445, 345),
    (New-Object System.Drawing.PointF 445, 575),
    (New-Object System.Drawing.PointF 640, 460)
)
$g.FillPolygon($play, $tri)

# Dashboard curve under the screen
$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 56
$pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$g.DrawArc($pen, 172, 740, 680, 260, 200, 140)

$g.Dispose()
$full = Join-Path (Get-Location) $Out
$bmp.Save($full, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "Wrote $full"
