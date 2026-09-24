# 生成 release 签名用的 keystore 与 key.properties
#
# 用途：替换项目默认的 debug 签名，使其成为可正式分发的 release 签名。
#
# ⚠️ 重要：keystore 文件和密码**绝不能提交到版本库**。
#    - key.properties 应在 .gitignore 里
#    - *.jks 也应在 .gitignore 里
#    丢失 keystore 将导致无法覆盖升级已发布的 App。
#
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File make-keystore.ps1 -ProjectRoot <路径>

param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    # keystore 的别名与组织信息
    [string]$Alias = 'hit-schedule',
    [string]$Dname = 'CN=Leocy, OU=Personal, O=HitClassSchedule, L=Harbin, ST=Heilongjiang, C=CN',
    [int]$ValidityDays = 10000
)

# 注意：keytool 把进度信息写到 stderr，PowerShell 会把它当成 error，
# 因此**不能**设 $ErrorActionPreference='Stop'，否则脚本会在生成成功前中止。
# 改用显式的 $LASTEXITCODE 检查。
$ErrorActionPreference = 'Continue'

$androidDir = Join-Path $ProjectRoot 'android'
$appDir = Join-Path $androidDir 'app'
$ksPath = Join-Path $appDir 'release-key.jks'
$propsPath = Join-Path $androidDir 'key.properties'
$keyPropsPath = Join-Path $env:USERPROFILE '.hit-class-schedule-keystore.txt'

# keytool 定位
$javaBin = Join-Path $env:JAVA_HOME 'bin'
if (-not (Test-Path (Join-Path $javaBin 'keytool.exe'))) {
    $found = Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Recurse -Filter 'keytool.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $found) { throw '找不到 keytool.exe，请确认已安装 JDK' }
    $javaBin = $found.DirectoryName
}
$env:Path = "$javaBin;$env:Path"

if (Test-Path $ksPath) {
    throw "keystore 已存在: $ksPath`n如需重新生成，请先手动删除（注意：删除后无法覆盖安装旧签名的 App）"
}

# 生成强随机密码（避免被猜测）
function New-StrongPassword([int]$len = 24) {
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $s = [Convert]::ToBase64String($bytes)
    $s = $s.Replace('/', '_').Replace('+', '-').Replace('=', '')
    return $s.Substring(0, $len)
}

$storePwd = New-StrongPassword
$keyPwd = $storePwd   # 简化：两者相同，避免混淆；如需要可分开

Write-Output '=== 生成 keystore ==='
# 2>&1 会把 keytool 的中文进度（GBK）混进输出，这里只取其退出码判断成败
$null = keytool -genkeypair `
    -keystore $ksPath `
    -alias $Alias `
    -keyalg RSA `
    -keysize 4096 `
    -validity $ValidityDays `
    -storepass $storePwd `
    -keypass $keyPwd `
    -dname $Dname `
    -storetype PKCS12 2>&1
$code = $LASTEXITCODE
Write-Output "  keytool 退出码: $code"

if (-not (Test-Path $ksPath)) { throw "keytool 未生成 keystore（退出码 $code）" }
Write-Output "  keystore 已生成: $((Get-Item $ksPath).Length) 字节"

# 写 key.properties（Gradle 读取；路径用正斜杠避免转义问题）
$propsContent = @"
# release 签名配置 —— 由 tool/make-keystore.ps1 生成
# ⚠️ 不要提交到版本库
storePassword=$storePwd
keyPassword=$keyPwd
keyAlias=$Alias
storeFile=release-key.jks
"@
[System.IO.File]::WriteAllText($propsPath, $propsContent, (New-Object System.Text.UTF8Encoding($false)))

# 另存一份凭据备份到用户目录（含密码），提醒用户妥善保存
$backupContent = @"
哈工大课表 —— release 签名凭据备份
生成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

keystore 文件: $ksPath
alias:         $Alias
storePassword: $storePwd
keyPassword:   $keyPwd
有效期:        $ValidityDays 天

⚠️ 请把这份信息和 keystore 文件一起妥善备份（如加密云盘）。
   丢失后将无法对已发布的 App 做覆盖升级，只能换包名重新发布。
"@
[System.IO.File]::WriteAllText($keyPropsPath, $backupContent, (New-Object System.Text.UTF8Encoding($true)))

Write-Output ''
Write-Output '=== 结果 ==='
Write-Output "  keystore:        $ksPath  ($((Get-Item $ksPath).Length) 字节)"
Write-Output "  key.properties:  $propsPath"
Write-Output "  凭据备份:        $keyPropsPath"
Write-Output ''
Write-Output '=== keystore 指纹 ==='
keytool -list -v -keystore $ksPath -storepass $storePwd -alias $Alias 2>&1 |
    Select-String -Pattern 'SHA1:|SHA256:|MD5:|Alias|Valid' | ForEach-Object { "  $($_.Line.Trim())" }
