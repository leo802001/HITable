# 从 H 图标生成 Android 各密度启动图标（含压缩）
#
# 处理要点：
# 1. 源图 2048x2048 无透明通道，右下角有「豆包AI生成」水印 → 内缩裁掉边缘
# 2. 背景是浅米白，与 Android 自适应图标要区分（这里做传统方图标）
# 3. 压缩：PNG 尺寸降下来后单张只有几 KB，总增量可忽略
#
# 用法: powershell -File make-h-icon.ps1 <源图> <项目根目录>
param(
    [Parameter(Mandatory = $true)][string]$SourceImage,
    [Parameter(Mandatory = $true)][string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$src = [System.Drawing.Image]::FromFile($SourceImage)
Write-Output "源图: $($src.Width) x $($src.Height)  $($src.PixelFormat)"

# ---- 1) 内缩裁掉外圈（去掉右下角水印 + 多余留白）----
# 按比例内缩：左右各收 6%，上下各收 6%，水印位于右下角，故底部多收一点
$insetX = [int]($src.Width * 0.06)
$insetTop = [int]($src.Height * 0.06)
$insetBottom = [int]($src.Height * 0.10)   # 底部多收，避开水印

$cropW = $src.Width - $insetX * 2
$cropH = $src.Height - $insetTop - $insetBottom
# 取正方形，以宽度为准
$side = [Math]::Min($cropW, $cropH)
$cropX = $insetX + [int](($cropW - $side) / 2)
$cropY = $insetTop + [int](($cropH - $side) / 2)
Write-Output "裁切区域: x=$cropX y=$cropY ${side}x${side}"

$square = [System.Drawing.Bitmap]::new($side, $side)
$g = [System.Drawing.Graphics]::FromImage($square)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$srcRect = [System.Drawing.Rectangle]::new($cropX, $cropY, $side, $side)
$dstRect = [System.Drawing.Rectangle]::new(0, 0, $side, $side)
$g.DrawImage($src, $dstRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()

# ---- 2) 各密度图标 ----
$resDir = Join-Path $ProjectRoot 'android\app\src\main\res'
$densities = [ordered]@{
    'mipmap-mdpi'    = 48
    'mipmap-hdpi'    = 72
    'mipmap-xhdpi'   = 96
    'mipmap-xxhdpi'  = 144
    'mipmap-xxxhdpi' = 192
}

function Resize-Save([System.Drawing.Image]$image, [int]$size, [string]$outPath) {
    $bmp = [System.Drawing.Bitmap]::new($size, $size)
    $gg = [System.Drawing.Graphics]::FromImage($bmp)
    $gg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $gg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $gg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $gg.DrawImage($image, 0, 0, $size, $size)
    $gg.Dispose()
    $dir = Split-Path $outPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

$totalBytes = 0
foreach ($d in $densities.GetEnumerator()) {
    $out = Join-Path $resDir "$($d.Key)\ic_launcher.png"
    Resize-Save $square $d.Value $out
    $sz = (Get-Item $out).Length
    $totalBytes += $sz
    Write-Output ("  {0,-18} {1,3}x{1,-3}  {2,6} 字节" -f $d.Key, $d.Value, $sz)
}

# ---- 3) 源图存档（1024，压缩后的）----
$iconDir = Join-Path $ProjectRoot 'assets\icon'
if (-not (Test-Path $iconDir)) { New-Item -ItemType Directory -Force -Path $iconDir | Out-Null }
Resize-Save $square 1024 (Join-Path $iconDir 'app_icon_source.png')
$bigSize = (Get-Item (Join-Path $iconDir 'app_icon_source.png')).Length
Write-Output ("  {0,-18} {1,3}x{1,-3}  {2,6} 字节" -f 'app_icon_source', 1024, $bigSize)

Write-Output ''
Write-Output "各密度图标合计: $totalBytes 字节 ($([math]::Round($totalBytes/1KB,1)) KB)"

$square.Dispose()
$src.Dispose()
Write-Output '完成'
