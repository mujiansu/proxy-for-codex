[CmdletBinding()]
param(
    [string]$OutputPath,
    [string]$PreviewPath
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$pluginRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if (-not $OutputPath) {
    $OutputPath = Join-Path $pluginRoot 'assets\proxy-icon.ico'
}
if (-not $PreviewPath) {
    $PreviewPath = Join-Path $pluginRoot '.test-runs\proxy-icon-preview.png'
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$PreviewPath = [System.IO.Path]::GetFullPath($PreviewPath)

function New-RoundedRectanglePath {
    param(
        [float]$X,
        [float]$Y,
        [float]$Width,
        [float]$Height,
        [float]$Radius
    )
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $diameter = $Radius * 2
    $path.AddArc($X, $Y, $diameter, $diameter, 180, 90)
    $path.AddArc($X + $Width - $diameter, $Y, $diameter, $diameter, 270, 90)
    $path.AddArc(
        $X + $Width - $diameter,
        $Y + $Height - $diameter,
        $diameter,
        $diameter,
        0,
        90
    )
    $path.AddArc($X, $Y + $Height - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-IconBitmap {
    param(
        [int]$Size,
        [switch]$TransparentBackground
    )
    $scale = $Size / 64.0
    $bitmap = [System.Drawing.Bitmap]::new(
        $Size,
        $Size,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.Clear([System.Drawing.Color]::Transparent)

        if (-not $TransparentBackground) {
            $outerPath = New-RoundedRectanglePath (2 * $scale) (2 * $scale) `
                (60 * $scale) (60 * $scale) (16 * $scale)
            $outerBrush = [System.Drawing.SolidBrush]::new(
                [System.Drawing.ColorTranslator]::FromHtml('#072A2A')
            )
            try {
                $graphics.FillPath($outerBrush, $outerPath)
            } finally {
                $outerBrush.Dispose()
                $outerPath.Dispose()
            }

            $innerPath = New-RoundedRectanglePath (4 * $scale) (4 * $scale) `
                (56 * $scale) (56 * $scale) (14 * $scale)
            $gradient = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
                [System.Drawing.RectangleF]::new(8 * $scale, 6 * $scale, 48 * $scale, 52 * $scale),
                [System.Drawing.ColorTranslator]::FromHtml('#0F766E'),
                [System.Drawing.ColorTranslator]::FromHtml('#0369A1'),
                45.0
            )
            try {
                $graphics.FillPath($gradient, $innerPath)
            } finally {
                $gradient.Dispose()
            }
            $border = [System.Drawing.Pen]::new(
                [System.Drawing.Color]::FromArgb(105, 94, 234, 212),
                [Math]::Max(0.75, 1.5 * $scale)
            )
            try {
                $graphics.DrawPath($border, $innerPath)
            } finally {
                $border.Dispose()
                $innerPath.Dispose()
            }
        }

        $route = [System.Drawing.Drawing2D.GraphicsPath]::new()
        $route.StartFigure()
        $route.AddLine(
            [System.Drawing.PointF]::new(16 * $scale, 20 * $scale),
            [System.Drawing.PointF]::new(28.5 * $scale, 20 * $scale)
        )
        $route.AddBezier(
            28.5 * $scale, 20 * $scale,
            31.9 * $scale, 20 * $scale,
            34.7 * $scale, 22.8 * $scale,
            34.7 * $scale, 26.2 * $scale
        )
        $route.AddLine(
            [System.Drawing.PointF]::new(34.7 * $scale, 26.2 * $scale),
            [System.Drawing.PointF]::new(34.7 * $scale, 28.6 * $scale)
        )
        $route.AddBezier(
            34.7 * $scale, 28.6 * $scale,
            34.7 * $scale, 31.2 * $scale,
            36.8 * $scale, 33.3 * $scale,
            39.4 * $scale, 33.3 * $scale
        )
        $route.AddLine(
            [System.Drawing.PointF]::new(39.4 * $scale, 33.3 * $scale),
            [System.Drawing.PointF]::new(47.5 * $scale, 33.3 * $scale)
        )
        $routeColor = if ($TransparentBackground) {
            [System.Drawing.ColorTranslator]::FromHtml('#0F766E')
        } else {
            [System.Drawing.ColorTranslator]::FromHtml('#D8FAF7')
        }
        $routePen = [System.Drawing.Pen]::new(
            $routeColor,
            [Math]::Max(1.2, 5.2 * $scale)
        )
        $routePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $routePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $routePen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
        try {
            $graphics.DrawPath($routePen, $route)
        } finally {
            $routePen.Dispose()
            $route.Dispose()
        }

        $startBrush = [System.Drawing.SolidBrush]::new(
            [System.Drawing.ColorTranslator]::FromHtml('#5EEAD4')
        )
        $endBrush = [System.Drawing.SolidBrush]::new(
            [System.Drawing.ColorTranslator]::FromHtml('#7DD3FC')
        )
        $centerBrush = [System.Drawing.SolidBrush]::new(
            $(if ($TransparentBackground) {
                [System.Drawing.Color]::White
            } else {
                [System.Drawing.ColorTranslator]::FromHtml('#F0FDFA')
            })
        )
        try {
            $graphics.FillEllipse(
                $startBrush,
                10.8 * $scale, 14.8 * $scale, 10.4 * $scale, 10.4 * $scale
            )
            $graphics.FillEllipse(
                $endBrush,
                41.8 * $scale, 27.6 * $scale, 11.2 * $scale, 11.2 * $scale
            )
            $graphics.FillEllipse(
                $centerBrush,
                14 * $scale, 18 * $scale, 4 * $scale, 4 * $scale
            )
            $graphics.FillEllipse(
                $centerBrush,
                45 * $scale, 31 * $scale, 4.2 * $scale, 4.2 * $scale
            )
        } finally {
            $startBrush.Dispose()
            $endBrush.Dispose()
            $centerBrush.Dispose()
        }
    } finally {
        $graphics.Dispose()
    }
    return $bitmap
}

function Convert-BitmapToPngBytes {
    param([System.Drawing.Bitmap]$Bitmap)
    $stream = [System.IO.MemoryStream]::new()
    try {
        $Bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        return $stream.ToArray()
    } finally {
        $stream.Dispose()
    }
}

$sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
$images = [System.Collections.Generic.List[object]]::new()
foreach ($size in $sizes) {
    $bitmap = New-IconBitmap $size
    try {
        $images.Add([pscustomobject]@{
            Size = $size
            Bytes = Convert-BitmapToPngBytes $bitmap
        })
    } finally {
        $bitmap.Dispose()
    }
}

New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null
$stream = [System.IO.File]::Open(
    $OutputPath,
    [System.IO.FileMode]::Create,
    [System.IO.FileAccess]::Write,
    [System.IO.FileShare]::None
)
try {
    $writer = [System.IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]$images.Count)
        $offset = 6 + (16 * $images.Count)
        foreach ($image in $images) {
            $dimension = if ($image.Size -ge 256) { 0 } else { $image.Size }
            $writer.Write([byte]$dimension)
            $writer.Write([byte]$dimension)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]32)
            $writer.Write([uint32]$image.Bytes.Length)
            $writer.Write([uint32]$offset)
            $offset += $image.Bytes.Length
        }
        foreach ($image in $images) {
            $writer.Write([byte[]]$image.Bytes)
        }
    } finally {
        $writer.Dispose()
    }
} finally {
    $stream.Dispose()
}

New-Item -ItemType Directory -Path (Split-Path -Parent $PreviewPath) -Force | Out-Null
$preview = New-IconBitmap 512
try {
    $preview.Save($PreviewPath, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    $preview.Dispose()
}

[pscustomobject]@{
    ok = $true
    icon = $OutputPath
    iconBytes = (Get-Item -LiteralPath $OutputPath).Length
    preview = $PreviewPath
    sizes = $sizes
} | ConvertTo-Json
