# cc 命令助手 PowerShell 脚本 - 纯 AI 模型版本
# 不使用预设规则，完全依赖模型判断

$OLLAMA_URL = "http://127.0.0.1:11434/v1"
$MODEL = "qwen2.5:1.5b"
$DEBUG = $false

if ($args.Count -lt 1) {
    Write-Host "用法: cc <中文需求>" -ForegroundColor Red
    Write-Host "示例: cc 我在哪个目录" -ForegroundColor Yellow
    exit 1
}

$userQuery = $args -join " "

if ($DEBUG) {
    Write-Host "[DEBUG] 查询: $userQuery" -ForegroundColor Gray
}

# 构建更精确的提示词
$prompt = @"
将以下中文需求转换为一条 Windows PowerShell 命令。
只输出命令本身，不要任何解释、不要代码块标记、不要额外文字。

需求：$userQuery

命令：
"@

$systemMsg = "你是一个 Windows PowerShell 命令转换助手。只输出命令，不要任何解释。"

$jsonBody = @{
    model = $MODEL
    messages = @(
        @{
            role = "system"
            content = $systemMsg
        },
        @{
            role = "user"
            content = $prompt
        }
    )
    temperature = 0
    max_tokens = 64
    stream = $false
} | ConvertTo-Json -Depth 10

if ($DEBUG) {
    Write-Host "[DEBUG] 发送请求..." -ForegroundColor Gray
}

try {
    # 使用 Invoke-RestMethod，确保正确处理 JSON
    $response = Invoke-RestMethod -Uri "$OLLAMA_URL/chat/completions" `
        -Method Post `
        -ContentType "application/json; charset=utf-8" `
        -Body $jsonBody `
        -ErrorAction Stop

    if ($DEBUG) {
        Write-Host "[DEBUG] 收到响应" -ForegroundColor Gray
    }

    if ($response.choices -and $response.choices.Count -gt 0 -and $response.choices[0].message.content) {
        $content = $response.choices[0].message.content
        
        if ($DEBUG) {
            Write-Host "[DEBUG] 原始内容: $content" -ForegroundColor Magenta
            Write-Host "[DEBUG] 内容长度: $($content.Length)" -ForegroundColor Gray
        }
        
        # 清理命令
        $cmd = $content.Trim()
        # 移除代码块标记
        $cmd = $cmd -replace '```powershell', '' -replace '```ps1', '' -replace '```bash', '' -replace '```shell', '' -replace '```', ''
        $cmd = $cmd.Trim()
        # 只取第一行
        $cmd = ($cmd -split "`n")[0].Trim()
        # 移除可能的"命令："前缀
        $cmd = $cmd -replace '^命令[:：]\s*', ''
        $cmd = $cmd.Trim()
        
        if ($DEBUG) {
            Write-Host "[DEBUG] 清理后: $cmd" -ForegroundColor Cyan
        }
        
        # 检查是否有效（不是全问号，不为空）
        $isValid = $false
        if (-not [string]::IsNullOrWhiteSpace($cmd)) {
            $questionCount = ($cmd.ToCharArray() | Where-Object { $_ -eq '?' }).Count
            # 如果问号少于30%，认为是有效的
            if ($questionCount -lt ($cmd.Length * 0.3)) {
                $isValid = $true
            }
        }
        
        if ($isValid) {
            Write-Host ""
            Write-Host "> AI 建议: " -ForegroundColor Green -NoNewline
            Write-Host $cmd -ForegroundColor White
            Write-Host ""
            
            $confirm = Read-Host "确认执行该命令吗？(y/Enter 执行, n 退出, d 调试)"
            
            if ($confirm -eq "d") {
                # 显示调试信息
                Write-Host ""
                Write-Host "=== 调试信息 ===" -ForegroundColor Yellow
                Write-Host "原始查询: $userQuery" -ForegroundColor Gray
                Write-Host "原始返回: $content" -ForegroundColor Gray
                Write-Host "清理后命令: $cmd" -ForegroundColor Gray
                Write-Host "命令长度: $($cmd.Length)" -ForegroundColor Gray
                Write-Host "问号数量: $questionCount" -ForegroundColor Gray
                Write-Host ""
                $confirm = Read-Host "是否执行？(y/n)"
            }
            
            if ([string]::IsNullOrWhiteSpace($confirm) -or $confirm -eq "y" -or $confirm -eq "yes") {
                Write-Host ""
                Write-Host "正在执行: $cmd" -ForegroundColor Yellow
                Write-Host ""
                try {
                    Invoke-Expression $cmd
                } catch {
                    Write-Host "执行错误: $($_.Exception.Message)" -ForegroundColor Red
                }
            } else {
                Write-Host "已取消执行。"
            }
        } else {
            Write-Host ""
            Write-Host "错误: 模型返回了无效命令" -ForegroundColor Red
            
            if ($DEBUG) {
                Write-Host ""
                Write-Host "=== 调试信息 ===" -ForegroundColor Yellow
                Write-Host "原始返回: $content" -ForegroundColor Gray
                Write-Host "清理后: $cmd" -ForegroundColor Gray
                Write-Host "问号数量: $questionCount / $($cmd.Length)" -ForegroundColor Gray
            } else {
                Write-Host ""
                Write-Host "提示: 编辑 cc.ps1，将 `$DEBUG = `$false 改为 `$DEBUG = `$true" -ForegroundColor Yellow
                Write-Host "      然后重新运行查看详细信息" -ForegroundColor Yellow
            }
            
            Write-Host ""
            Write-Host "常用命令参考：" -ForegroundColor Cyan
            Write-Host "  Get-Location          # 查看当前目录" -ForegroundColor Gray
            Write-Host "  Get-ChildItem         # 列出文件" -ForegroundColor Gray
            Write-Host "  Get-Process           # 查看进程" -ForegroundColor Gray
            Write-Host "  Get-Service           # 查看服务" -ForegroundColor Gray
            Write-Host "  Get-Date              # 查看时间" -ForegroundColor Gray
        }
    } else {
        Write-Host "错误: 模型未返回内容" -ForegroundColor Red
        if ($DEBUG) {
            Write-Host "[DEBUG] 响应对象: $($response | ConvertTo-Json -Depth 5)" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "错误: $($_.Exception.Message)" -ForegroundColor Red
    
    if ($DEBUG) {
        Write-Host "[DEBUG] 详细错误:" -ForegroundColor Red
        Write-Host $_.Exception -ForegroundColor Red
    }
    
    # 检查 Ollama 是否运行
    Write-Host ""
    Write-Host "请确认：" -ForegroundColor Yellow
    Write-Host "  1. Ollama 服务是否运行？" -ForegroundColor Gray
    Write-Host "  2. 模型 $MODEL 是否已安装？" -ForegroundColor Gray
    Write-Host ""
    Write-Host "检查命令：" -ForegroundColor Cyan
    Write-Host "  ollama list           # 查看已安装模型" -ForegroundColor Gray
    Write-Host "  ollama serve          # 启动服务" -ForegroundColor Gray
}

