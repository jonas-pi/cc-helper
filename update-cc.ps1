# 更新 cc.ps1 脚本（使用正确的 UTF-8 编码）

$url = "https://raw.githubusercontent.com/jonas-pi/cc-helper/main/cc.ps1"
$outputPath = "$env:USERPROFILE\cc.ps1"

Write-Host "正在下载 cc.ps1..." -ForegroundColor Yellow

try {
    # 使用 UTF-8 编码下载
    $content = Invoke-WebRequest -Uri $url -UseBasicParsing | Select-Object -ExpandProperty Content
    
    # 使用 UTF-8 with BOM 编码保存（PowerShell 推荐）
    $utf8WithBom = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($outputPath, $content, $utf8WithBom)
    
    Write-Host "✓ cc.ps1 已更新到: $outputPath" -ForegroundColor Green
    Write-Host ""
    Write-Host "现在可以运行: cc 我在哪个目录" -ForegroundColor Cyan
} catch {
    Write-Host "✗ 下载失败: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

