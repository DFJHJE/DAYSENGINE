# Generates the iOS app icon set by drawing the PNGs directly with System.Drawing.
#
#   powershell -ExecutionPolicy Bypass -File ios\tools\make-icon.ps1
#
# Earlier revisions shelled out to headless Edge to rasterise an SVG. That proved unreliable
# here: Edge's --screenshot mode intermittently hangs part-way through a batch and leaves
# renderer processes behind. System.Drawing draws the same mark deterministically in well under
# a second per size with no external process.
#
# ASCII-only on purpose: Windows PowerShell 5.1 parses a BOM-less script as ANSI, which
# corrupts non-ASCII characters and breaks the parser.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ios = Split-Path -Parent $here
$iconSet = Join-Path $ios 'DaysEngine\Assets.xcassets\AppIcon.appiconset'
New-Item -ItemType Directory -Force -Path $iconSet | Out-Null

# Clear out anything a previous run left behind, so a stale 1024 cannot mask a failed render.
Get-ChildItem $iconSet -Filter '*.png' -ErrorAction SilentlyContinue | Remove-Item -Force

function New-Icon([int] $size, [string] $path) {
    $bmp = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    $s = [double]$size / 1024.0

    # Background: the launcher's own gradient.
    $rect = [System.Drawing.Rectangle]::new(0, 0, $size, $size)
    $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        $rect,
        [System.Drawing.Color]::FromArgb(255, 0x1a, 0x1a, 0x2e),
        [System.Drawing.Color]::FromArgb(255, 0x0f, 0x34, 0x60),
        [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal)
    $g.FillRectangle($brush, $rect)
    $brush.Dispose()

    # Accent ring behind the note.
    $ringPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(46, 0xff, 0x6b, 0x8a), [single](26 * $s))
    $g.DrawEllipse($ringPen, [single](212 * $s), [single](170 * $s), [single](600 * $s), [single](600 * $s))
    $ringPen.Dispose()

    # The note, filled with the accent gradient. Two heads, two stems, one beam.
    $noteRect = [System.Drawing.Rectangle]::new([int](234 * $s), [int](166 * $s), [int](606 * $s + 1), [int](630 * $s + 1))
    $noteBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        $noteRect,
        [System.Drawing.Color]::FromArgb(255, 0xff, 0x8f, 0xa3),
        [System.Drawing.Color]::FromArgb(255, 0xff, 0x6b, 0x8a),
        [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal)

    $g.FillEllipse($noteBrush, [single](234 * $s), [single](604 * $s), [single](236 * $s), [single](192 * $s))
    $g.FillEllipse($noteBrush, [single](582 * $s), [single](532 * $s), [single](236 * $s), [single](192 * $s))
    $g.FillRectangle($noteBrush, [single](446 * $s), [single](238 * $s), [single](46 * $s), [single](468 * $s))
    $g.FillRectangle($noteBrush, [single](794 * $s), [single](166 * $s), [single](46 * $s), [single](468 * $s))

    $beam = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $beam.AddPolygon([System.Drawing.PointF[]]@(
        [System.Drawing.PointF]::new([single](446 * $s), [single](238 * $s)),
        [System.Drawing.PointF]::new([single](840 * $s), [single](166 * $s)),
        [System.Drawing.PointF]::new([single](840 * $s), [single](258 * $s)),
        [System.Drawing.PointF]::new([single](446 * $s), [single](330 * $s))
    ))
    $g.FillPath($noteBrush, $beam)
    $beam.Dispose()
    $noteBrush.Dispose()

    # The wordmark, only where it stays legible.
    if ($size -ge 152) {
        $fontSize = [single](92 * $s)
        $font = [System.Drawing.Font]::new('Helvetica Neue', $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $textBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 0xe0, 0xe0, 0xe0))
        $format = [System.Drawing.StringFormat]::new()
        $format.Alignment = [System.Drawing.StringAlignment]::Center
        $g.DrawString('DaysEngine', $font, $textBrush, [single](512 * $s), [single](862 * $s), $format)
        $format.Dispose()
        $textBrush.Dispose()
        $font.Dispose()
    }

    $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

$sizes = @(
    @{ name = 'AppIcon-1024.png'; px = 1024 },
    @{ name = 'AppIcon-180.png';  px = 180  },
    @{ name = 'AppIcon-120.png';  px = 120  },
    @{ name = 'AppIcon-167.png';  px = 167  },
    @{ name = 'AppIcon-152.png';  px = 152  },
    @{ name = 'AppIcon-76.png';   px = 76   },
    @{ name = 'AppIcon-40.png';   px = 40   },
    @{ name = 'AppIcon-29.png';   px = 29   }
)

foreach ($size in $sizes) {
    $target = Join-Path $iconSet $size.name
    New-Icon $size.px $target
    Write-Host ("  {0,-18} {1,5}x{1,-5} {2,9:N0} bytes" -f $size.name, $size.px, (Get-Item $target).Length)
}

# iOS 17+ reads the single 1024 entry; the named entries fill the classic slots so an older
# Xcode does not complain about a missing icon.
$manifest = @'
{
  "images" : [
    { "filename" : "AppIcon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "filename" : "AppIcon-180.png", "idiom" : "iphone", "scale" : "3x", "size" : "60x60" },
    { "filename" : "AppIcon-120.png", "idiom" : "iphone", "scale" : "2x", "size" : "60x60" },
    { "filename" : "AppIcon-167.png", "idiom" : "ipad", "scale" : "2x", "size" : "83.5x83.5" },
    { "filename" : "AppIcon-152.png", "idiom" : "ipad", "scale" : "2x", "size" : "76x76" },
    { "filename" : "AppIcon-76.png", "idiom" : "ipad", "scale" : "1x", "size" : "76x76" },
    { "filename" : "AppIcon-40.png", "idiom" : "ipad", "scale" : "1x", "size" : "40x40" },
    { "filename" : "AppIcon-29.png", "idiom" : "ipad", "scale" : "1x", "size" : "29x29" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
'@
[System.IO.File]::WriteAllText((Join-Path $iconSet 'Contents.json'), $manifest, (New-Object System.Text.UTF8Encoding($false)))

$catalog = @'
{
  "info" : { "author" : "xcode", "version" : 1 }
}
'@
[System.IO.File]::WriteAllText((Join-Path $ios 'DaysEngine\Assets.xcassets\Contents.json'), $catalog, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ''
Write-Host "Icons written to $iconSet" -ForegroundColor Green
Write-Host ("{0} PNGs + Contents.json" -f (Get-ChildItem $iconSet -Filter '*.png').Count)
