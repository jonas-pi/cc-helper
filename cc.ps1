# cc 命令助手 PowerShell 脚本

# Ollama 配置
$OLLAMA_URL = "http://127.0.0.1:11434/v1"
$MODEL = "phi3.5"

# 检查并自动选择可用模型
function Check-And-Select-Model {
    # 检查当前配置的模型是否存在
    $modelList = ollama list 2>$null
    if ($modelList -and $modelList -match [regex]::Escape($MODEL)) {
        return $true
    }
    
    # 如果配置的模型不存在，尝试从已安装的模型中选择
    if (-not $modelList) {
        Write-Host "ERROR: 未找到已安装的模型" -ForegroundColor Red
        Write-Host "请运行: ollama pull phi3.5" -ForegroundColor Gray
        return $false
    }
    
    $availableModels = $modelList | Select-Object -Skip 1 | ForEach-Object {
        ($_ -split '\s+')[0]
    } | Where-Object { $_ -ne "" }
    
    if ($availableModels.Count -eq 0) {
        Write-Host "ERROR: 未找到已安装的模型" -ForegroundColor Red
        Write-Host "请运行: ollama pull phi3.5" -ForegroundColor Gray
        return $false
    }
    
    # 优先级列表（Windows优先推荐PowerShell友好的模型）
    $priorityModels = @("phi3.5", "llama3.2:3b", "llama3.2:1b", "qwen2.5:1.5b", "qwen2.5:3b", "qwen2.5:0.5b", "qwen2.5:7b")
    
    # 从优先级列表中找到第一个已安装的模型
    foreach ($preferred in $priorityModels) {
        if ($availableModels -contains $preferred) {
            $script:MODEL = $preferred
            Write-Host "注意: 使用模型 $MODEL" -ForegroundColor Yellow
            return $true
        }
    }
    
    # 如果优先级列表中都没有，使用第一个可用的模型
    $script:MODEL = $availableModels[0]
    Write-Host "注意: 使用模型 $MODEL" -ForegroundColor Yellow
    return $true
}

# 清理命令输出
function Sanitize-Command {
    param([string]$cmd)
    if ([string]::IsNullOrWhiteSpace($cmd)) {
        return ""
    }
    
    # 移除代码块标记
    $cmd = $cmd -replace '```powershell', '' -replace '```ps1', '' -replace '```bash', '' -replace '```shell', '' -replace '```', ''
    $cmd = $cmd.Trim()
    $cmd = $cmd -replace '\\$', ''
    
    # 只取第一行
    $lines = $cmd -split "`n", 2
    $cmd = $lines[0].Trim()
    
    # 移除提示词残留
    $cmd = $cmd -replace '^Windows Power.*?:', '' -replace '^只输出命令.*?:', '' -replace '^命令.*?:', ''
    $cmd = $cmd -replace '^你是一个.*?:', '' -replace '^PowerShell.*?:', ''
    
    # 移除冒号格式
    if ($cmd -match '^[^:]+:\s*(.+)$') {
        $cmd = $matches[1].Trim()
    }
    
    # 最终清理
    $cmd = $cmd.Trim()
    return $cmd
}

# 获取命令
function Get-AICommand {
    param([string]$query)
    
    # 针对 phi3.5 优化的提示词
    $prompt = @"
Convert the following Chinese request into a single PowerShell command.
Output ONLY the command, without any explanation, markdown, code blocks, or extra text.

Request in Chinese: $query

PowerShell Command:
"@

    $systemMsg = "You are a PowerShell assistant. Output only the PowerShell command, nothing else."
    
    # 构建 JSON
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
        temperature = 0.1
        max_tokens = 64
    } | ConvertTo-Json -Depth 10

    # 调用 Ollama API
    try {
        $response = Invoke-RestMethod -Uri "$OLLAMA_URL/chat/completions" `
            -Method Post `
            -ContentType "application/json" `
            -Body $jsonBody `
            -ErrorAction Stop

        if ($response.choices -and $response.choices.Count -gt 0 -and $response.choices[0].message.content) {
            $content = $response.choices[0].message.content
            if ($content -is [string]) {
                $content = $content.Trim()
            } else {
                $content = $content.ToString().Trim()
            }
            
            return $content
        } else {
            return "ERROR: 模型无响应"
        }
    } catch {
        return "ERROR: $($_.Exception.Message)"
    }
}

# 主函数
$firstArg = if ($args.Count -gt 0) { $args[0] } else { "" }

# 预设指令: hello（不依赖模型）
if ($firstArg -eq "hello") {
    Write-Host "cc v1.0 | $MODEL" -ForegroundColor Gray
    exit 0
}

# 预设指令: -u 更新（不依赖模型）
if ($firstArg -eq "-u" -or $firstArg -eq "update" -or $firstArg -eq "--update") {
    Write-Host "updating..." -ForegroundColor Gray
    try {
        $url = "https://raw.githubusercontent.com/jonas-pi/cc-helper/main/cc.ps1"
        $outputPath = "$env:USERPROFILE\cc.ps1"
        
        # 备份当前文件
        if (Test-Path $outputPath) {
            Copy-Item $outputPath "$outputPath.backup" -Force | Out-Null
        }

        # 使用 WebClient 并明确指定 UTF-8 编码下载
        $webClient = New-Object System.Net.WebClient
        $webClient.Encoding = [System.Text.Encoding]::UTF8
        $content = $webClient.DownloadString($url)
        
        # 根据控制台编码选择保存编码
        $currentEncoding = [Console]::OutputEncoding
        $saveEncoding = $null
        if ($currentEncoding.CodePage -eq 936) { # GBK/GB2312
            $saveEncoding = [System.Text.Encoding]::GetEncoding(936)
        } else { # UTF-8 with BOM
            $saveEncoding = New-Object System.Text.UTF8Encoding $true
        }
        
        [System.IO.File]::WriteAllText($outputPath, $content, $saveEncoding)
        Write-Host "updated" -ForegroundColor Gray
    } catch {
        Write-Host "failed" -ForegroundColor Red
        exit 1
    }
    exit 0
}

# 帮助信息
if ($args.Count -lt 1 -or $firstArg -eq "-h" -or $firstArg -eq "--help") {
    Write-Host "用法: cc <中文需求>" -ForegroundColor Gray
    Write-Host "示例: cc 我在哪个目录" -ForegroundColor Gray
    Write-Host "" -ForegroundColor Gray
    Write-Host "预设指令:" -ForegroundColor Gray
    Write-Host "  cc hello     - 显示版本信息" -ForegroundColor Gray
    Write-Host "  cc -u        - 更新脚本" -ForegroundColor Gray
    Write-Host "  cc -change   - 切换模型" -ForegroundColor Gray
    Write-Host "  cc -add      - 安装新模型" -ForegroundColor Gray
    Write-Host "  cc -del      - 删除模型" -ForegroundColor Gray
    exit 1
}

$userQuery = $args -join " "

# 检查并选择可用模型
if (-not (Check-And-Select-Model)) {
    exit 1
}

$cmd = Get-AICommand $userQuery

if ($cmd -match "^ERROR:") {
    Write-Host $cmd -ForegroundColor Red
    exit 1
}

$cmd = Sanitize-Command $cmd

if ([string]::IsNullOrWhiteSpace($cmd)) {
    Write-Host "ERROR: 空命令" -ForegroundColor Red
    exit 1
}

Write-Host "> $cmd" -ForegroundColor Gray

$confirm = Read-Host "[y/n]"
if ([string]::IsNullOrWhiteSpace($confirm) -or $confirm -eq "y" -or $confirm -eq "yes") {
    Invoke-Expression $cmd
}
