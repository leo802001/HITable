# 把 1024 存档图压到更小（用 JPEG 质量 92 + PNG 调优对比）
# 目的：assets/icon/ 只是源码存档，不需保留无损大图
param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$iconDir = Join-Path $ProjectRoot 'assets\icon'
$srcPath = Join-Path $iconDir 'app_icon_source.png'
$img = [System.Drawing.Image]::FromFile($srcPath)
$before = (Get-Item $srcPath).Length
Write-Output "原存档: $before 字节"

# --- JPEG q=92 ---
$jpgPath = Join-Path $iconDir 'app_icon_source.jpg'
$enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
    Where-Object { $_.MimeType -eq 'image/jpeg' }
$params = [System.Drawing.Imaging.EncoderParameters]::new(1)
$params.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new(
    [System.Drawing.Imaging.Encoder]::Quality, [long]92)
$bmp = [System.Drawing.Bitmap]::new($img.Width, $img.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
# 白底（JPEG 不支持透明）
$g.Clear([System.Drawing.Color]::White)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($img, 0, 0, $img.Width, $img.Height)
$g.Dispose()
$bmp.Save($jpgPath, $enc, $params)
$bmp.Dispose()
$params.Dispose()

$jpgSize = (Get-Item $jpgPath).Length
Write-Output "JPEG q92 : $jpgSize 字节 ($([math]::Round($jpgSize/1KB,1)) KB)"

# 保留 JPEG（更小），删掉大 PNG
if ($jpgSize -lt $before) {
    Remove-Item $srcPath -Force
    Write-Output "已用 JPEG 替换 PNG 存档（省 $([math]::Round(($before-$jpgSize)/1KB,1)) KB）"
} else {
    Remove-Item $jpgPath -Force
    Write-Output "JPEG 反而更大，保留原 PNG"
}

$img.Dispose()
Write-Output ''
Write-Output '=== assets/icon 最终内容 ==='
Get-ChildItem $iconDir | ForEach-Object {
    Write-Output ("  {0,-26} {1,8} 字节" -f $_.Name, $_.Length)
}
