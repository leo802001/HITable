# 从图标源图生成 Android 各密度启动图标（先裁主体 → 再按比例居中留白 → 压缩）
#
# 关键设计：**不要**把主体裁到贴边。
# 实测上一版按包围盒精确裁切后，H 的边距为 0px（完全顶到边缘），
# 小尺寸下显得拥挤、且某些启动器圆角遮罩会切到笔画。
#
# 正确做法：
#   1) 从源图裁出主体（去掉原图自带的一大圈留白，避免主体过小）
#   2) 把主体**按比例缩小**到画布的 CONTENT_RATIO 左右
#   3) 居中放到背景色画布上，形成均匀安全边距
#
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File make-icon.ps1 -SourceImage <源图> -ProjectRoot <项目根>

param(
    [Parameter(Mandatory = $true)][string]$SourceImage,
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    # 主体在成品图标中占画布的比例（0.5~0.8 之间比较好看）
    [double]$ContentRatio = 0.62,
    # 背景填充色（源图实测背景为 #FEFEF7 米白）
    [string]$BackgroundHex = 'FEFEF7',
    # 实测主体包围盒；留空则自动探测
    [int]$CropX = -1,
    [int]$CropY = -1,
    [int]$CropSide = -1
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$src = [System.Drawing.Image]::FromFile($SourceImage)
Write-Output "源图: $($src.Width) x $($src.Height)"

# ---- 1) 定位主体 ----
if ($CropSide -gt 0) {
    $cropX = $CropX; $cropY = $CropY; $side = $CropSide
    Write-Output "使用指定主体区域: x=$cropX y=$cropY ${side}x${side}"
} else {
    # 自动探测：以左上角为背景基准，找出非背景像素的包围盒。
    #
    # ⚠️ 必须用 `new Bitmap($src)` 建**独立副本**再 Dispose ——
    # 直接把 $src 强转成 Bitmap 后 Dispose，会连带释放底层 GDI+ 图像，
    # 导致后面用 $src 绘制时抛 "Parameter is not valid"。
    $probe = New-Object System.Drawing.Bitmap($src)
    $bg = $probe.GetPixel(0, 0)
    $thr = 18
    $minX = $src.Width; $minY = $src.Height; $maxX = 0; $maxY = 0
    for ($y = 0; $y -lt $src.Height; $y += 2) {
        for ($x = 0; $x -lt $src.Width; $x += 2) {
            $c = $probe.GetPixel($x, $y)
            $d = [Math]::Abs($c.R - $bg.R) + [Math]::Abs($c.G - $bg.G) + [Math]::Abs($c.B - $bg.B)
            if ($d -gt $thr) {
                if ($x -lt $minX) { $minX = $x }
                if ($x -gt $maxX) { $maxX = $x }
                if ($y -lt $minY) { $minY = $y }
                if ($y -gt $maxY) { $maxY = $y }
            }
        }
    }
    $probe.Dispose()
    $cropX = $minX; $cropY = $minY
    $side = [Math]::Min($maxX - $minX, $maxY - $minY)
    Write-Output "自动探测主体: x=$cropX y=$cropY 边长=$side"
}

# 主体（正方形，高分辨率，供高质量缩放）
$subject = [System.Drawing.Bitmap]::new($side, $side)
$gs = [System.Drawing.Graphics]::FromImage($subject)
$gs.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gs.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$gs.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$gs.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$gs.DrawImage(
    $src,
    [System.Drawing.Rectangle]::new(0, 0, $side, $side),
    [System.Drawing.Rectangle]::new($cropX, $cropY, $side, $side),
    [System.Drawing.GraphicsUnit]::Pixel
)
$gs.Dispose()

# 背景色
$bgColor = [System.Drawing.Color]::FromArgb(
    [Convert]::ToInt32($BackgroundHex.Substring(0, 2), 16),
    [Convert]::ToInt32($BackgroundHex.Substring(2, 2), 16),
    [Convert]::ToInt32($BackgroundHex.Substring(4, 2), 16)
)
Write-Output "背景色: #$BackgroundHex"
Write-Output "主体占画布: $([math]::Round($ContentRatio*100,0))%"

# ---- 2) 按目标尺寸生成：主体缩放后居中贴到背景画布 ----
$resDir = Join-Path $ProjectRoot 'android\app\src\main\res'
$densities = [ordered]@{
    'mipmap-mdpi'    = 48
    'mipmap-hdpi'    = 72
    'mipmap-xhdpi'   = 96
    'mipmap-xxhdpi'  = 144
    'mipmap-xxxhdpi' = 192
}

function Compose-Icon([int]$canvas, [string]$outPath) {
    $bmp = [System.Drawing.Bitmap]::new($canvas, $canvas)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

    # 先铺背景
    $g.Clear($bgColor)

    # 再把主体按比例居中绘制
    $content = [int][Math]::Round($canvas * $ContentRatio)
    $offset = [int][Math]::Round(($canvas - $content) / 2.0)
    $g.DrawImage($subject, $offset, $offset, $content, $content)
    $g.Dispose()

    $dir = Split-Path $outPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

$totalBytes = 0
foreach ($d in $densities.GetEnumerator()) {
    $out = Join-Path $resDir "$($d.Key)\ic_launcher.png"
    Compose-Icon $d.Value $out
    $sz = (Get-Item $out).Length
    $totalBytes += $sz
    $margin = [int][Math]::Round($d.Value * (1 - $ContentRatio) / 2.0)
    Write-Output ("  {0,-18} {1,3}x{1,-3}  {2,6} 字节  边距约 {3}px" -f $d.Key, $d.Value, $sz, $margin)
}

# ---- 3) 存档图（1024 JPEG，不参与 APK，仅存档）----
$iconDir = Join-Path $ProjectRoot 'assets\icon'
if (-not (Test-Path $iconDir)) { New-Item -ItemType Directory -Force -Path $iconDir | Out-Null }
$archiveBmp = [System.Drawing.Bitmap]::new(1024, 1024)
$ga = [System.Drawing.Graphics]::FromImage($archiveBmp)
$ga.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$ga.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$ga.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$ga.Clear($bgColor)
$acontent = [int](1024 * $ContentRatio)
$aoffset = [int]((1024 - $acontent) / 2.0)
$ga.DrawImage($subject, $aoffset, $aoffset, $acontent, $acontent)
$ga.Dispose()
$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$params = New-Object System.Drawing.Imaging.EncoderParameters(1)
$params.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, 88)
$archive = Join-Path $iconDir 'app_icon_source.jpg'
$archiveBmp.Save($archive, $codec, $params)
$archiveBmp.Dispose()
Write-Output ("  {0,-18} {1,3}x{1,-3}  {2,6} 字节（JPEG 存档）" -f 'app_icon_source', 1024, (Get-Item $archive).Length)

Write-Output ''
Write-Output "各密度图标合计: $totalBytes 字节 ($([math]::Round($totalBytes/1KB,1)) KB)"

$subject.Dispose()
$src.Dispose()
Write-Output '完成'
