# cc 命令助手 PowerShell 脚本
# 基于 Linux 版本移植

# Ollama 配置
$OLLAMA_URL = "http://127.0.0.1:11434/v1"
$MODEL = "qwen2.5:1.5b"

# 颜色定义
function Write-Red($text) { Write-Host $text -ForegroundColor Red }
function Write-Green($text) { Write-Host $text -ForegroundColor Green }
function Write-Yellow($text) { Write-Host $text -ForegroundColor Yellow }

# 清理命令输出
function Sanitize-Command {
    param([string]$cmd)
    
    # 移除代码块标记
    $cmd = $cmd -replace '```powershell', '' -replace '```ps1', '' -replace '```bash', '' -replace '```shell', '' -replace '```', ''
    # 移除语言标识
    $cmd = $cmd -replace 'powershell', '' -replace 'ps1', '' -replace 'bash', '' -replace 'shell', ''
    # 移除首尾空白
    $cmd = $cmd.Trim()
    # 移除末尾的反斜杠
    $cmd = $cmd -replace '\\$', ''
    # 只取第一行
    $cmd = ($cmd -split "`n")[0].Trim()
    # 再次清理
    $cmd = $cmd.Trim()
    
    return $cmd
}

# 获取命令
function Get-AICommand {
    param([string]$query)
    
    # 构建提示词（与 Linux 版本一致）
    $prompt = @"
将中文需求转换为一条可直接执行的 Windows PowerShell 命令。
只输出命令，不要解释、不要 Markdown、不要占位符。
如果缺少参数，使用最常见的默认命令。

需求：
$query

命令：
"@

    $systemMsg = "你是一个 Windows PowerShell 命令转换助手。只输出命令，不要任何解释。"
    
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
        temperature = 0
        max_tokens = 64
    } | ConvertTo-Json -Depth 10

    # 调用 Ollama API
    try {
        $response = Invoke-RestMethod -Uri "$OLLAMA_URL/chat/completions" `
            -Method Post `
            -ContentType "application/json; charset=utf-8" `
            -Body $jsonBody `
            -ErrorAction Stop

        if ($response.choices -and $response.choices.Count -gt 0 -and $response.choices[0].message.content) {
            $content = $response.choices[0].message.content.Trim()
            return $content
        } else {
            return "ERROR: empty model output"
        }
    } catch {
        $errorMsg = $_.Exception.Message
        if ($_.ErrorDetails.Message) {
            try {
                $errorObj = $_.ErrorDetails.Message | ConvertFrom-Json
                if ($errorObj.error.message) {
                    $errorMsg = $errorObj.error.message
                }
            } catch {}
        }
        return "ERROR: $errorMsg"
    }
}

# 主函数
function Main {
    if ($args.Count -lt 1) {
        Write-Host "用法: cc <中文需求>" -ForegroundColor Red
        exit 1
    }

    $userQuery = $args -join " "
    $cmd = Get-AICommand $userQuery

    # 检查错误
    if ($cmd -match "^ERROR:") {
        Write-Red $cmd
        exit 1
    }

    # 清理命令
    $cmd = Sanitize-Command $cmd

    if ([string]::IsNullOrWhiteSpace($cmd)) {
        Write-Red "错误: 模型返回了空命令"
        exit 1
    }

    Write-Host ""
    Write-Green "> AI 建议: $cmd"
    Write-Host ""

    $confirm = Read-Host "确认执行该命令吗？(y/Enter 执行, n 退出)"
    if ([string]::IsNullOrWhiteSpace($confirm) -or $confirm -eq "y" -or $confirm -eq "yes") {
        Write-Host ""
        Write-Yellow "正在执行: $cmd"
        Write-Host ""
        Invoke-Expression $cmd
    } else {
        Write-Host "已取消执行。"
    }
}

# 执行主函数
Main @args
