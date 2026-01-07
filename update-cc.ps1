# 更新 cc.ps1 脚本（使用正确的 UTF-8 编码）

$url = "https://raw.githubusercontent.com/jonas-pi/cc-helper/main/cc-ai.ps1"
$outputPath = "$env:USERPROFILE\cc.ps1"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  更新 cc 命令助手" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 检测当前控制台编码
$currentEncoding = [Console]::OutputEncoding
Write-Host "当前控制台编码: $($currentEncoding.EncodingName)" -ForegroundColor Gray
Write-Host "CodePage: $($currentEncoding.CodePage)" -ForegroundColor Gray
Write-Host ""

Write-Host "正在下载 cc.ps1..." -ForegroundColor Yellow

try {
    # 使用 WebClient 并明确指定 UTF-8 编码下载
    $webClient = New-Object System.Net.WebClient
    $webClient.Encoding = [System.Text.Encoding]::UTF8
    $content = $webClient.DownloadString($url)
    
    # 根据控制台编码选择保存编码
    # 如果控制台是 GBK/GB2312，使用 GBK 保存；否则使用 UTF-8
    $saveEncoding = $null
    $encodingName = ""
    
    Write-Host "[调试] CodePage = $($currentEncoding.CodePage)" -ForegroundColor DarkGray
    
    if ($currentEncoding.CodePage -eq 936) {
        # GBK/GB2312 编码（中文 Windows 默认）
        $saveEncoding = [System.Text.Encoding]::GetEncoding(936)
        $encodingName = "GBK (GB2312)"
        Write-Host "[编码选择] 检测到 GBK 控制台，使用 GBK 编码保存" -ForegroundColor Yellow
    } else {
        # 其他编码使用 UTF-8 with BOM
        $saveEncoding = New-Object System.Text.UTF8Encoding $true
        $encodingName = "UTF-8 with BOM"
        Write-Host "[编码选择] 使用 UTF-8 编码保存（CodePage: $($currentEncoding.CodePage)）" -ForegroundColor Yellow
    }
    
    [System.IO.File]::WriteAllText($outputPath, $content, $saveEncoding)
    
    Write-Host "✓ cc.ps1 已更新到: $outputPath" -ForegroundColor Green
    Write-Host "✓ 使用编码: $encodingName" -ForegroundColor Green
    Write-Host ""
    
    # 验证文件内容（使用匹配的编码读取）
    $testContent = $null
    if ($currentEncoding.CodePage -eq 936) {
        # GBK 编码读取
        $testContent = [System.IO.File]::ReadAllText($outputPath, [System.Text.Encoding]::GetEncoding(936))
    } else {
        # UTF-8 编码读取
        $testContent = [System.IO.File]::ReadAllText($outputPath, [System.Text.Encoding]::UTF8)
    }
    
    if ($testContent -match '[\u4e00-\u9fff]' -or $testContent.Contains("目录") -or $testContent.Contains("文件")) {
        Write-Host "✓ 中文字符验证成功" -ForegroundColor Green
    } else {
        Write-Host "⚠ 警告: 未检测到中文字符，可能存在编码问题" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "现在可以运行: cc 我在哪个目录" -ForegroundColor Cyan
    Write-Host ""
} catch {
    Write-Host "✗ 下载失败: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "请尝试手动创建文件，运行以下命令：" -ForegroundColor Yellow
    Write-Host "notepad `$env:USERPROFILE\cc.ps1" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "然后访问以下网址复制内容：" -ForegroundColor Yellow
    Write-Host "https://raw.githubusercontent.com/jonas-pi/cc-helper/main/cc-simple.ps1" -ForegroundColor Cyan
    exit 1
}

