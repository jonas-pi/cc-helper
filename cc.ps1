# cc 命令助手 PowerShell 脚本

# Ollama 配置
$OLLAMA_URL = "http://127.0.0.1:11434/v1"
$MODEL = "qwen2.5:1.5b"

# 调试模式（设置为 $true 可以看到原始返回）
$DEBUG = $false

# 清理命令输出
function Sanitize-Command {
    param([string]$cmd)
    if ([string]::IsNullOrWhiteSpace($cmd)) {
        return ""
    }
    
    # 调试输出
    if ($DEBUG) {
        Write-Host "[DEBUG] 原始内容: $cmd" -ForegroundColor Gray
    }
    
    # 移除代码块标记
    $cmd = $cmd -replace '```powershell', '' -replace '```ps1', '' -replace '```bash', '' -replace '```shell', '' -replace '```', ''
    $cmd = $cmd.Trim()
    $cmd = $cmd -replace '\\$', ''
    
    # 只取第一行
    $lines = $cmd -split "`n", 2
    $cmd = $lines[0].Trim()
    
    # 移除提示词残留
    $cmd = $cmd -replace '^Windows Power.*?:', '' -replace '^只输出命令.*?:', '' -replace '^命令.*?:', '' -replace '^将中文需求.*?:', ''
    $cmd = $cmd -replace '^你是一个.*?:', '' -replace '^转换助手.*?:', '' -replace '^Windows.*?:', ''
    
    # 移除冒号格式
    if ($cmd -match '^[^:]+:\s*(.+)$') {
        $cmd = $matches[1].Trim()
    }
    
    # 检测问题内容（大量中文字符或问号）
    $chineseCount = ([regex]::Matches($cmd, '[\u4e00-\u9fff]')).Count
    $questionMarkCount = ([regex]::Matches($cmd, '\?')).Count
    
    if ($chineseCount -gt 3 -or $questionMarkCount -gt 2) {
        if ($DEBUG) {
            Write-Host "[DEBUG] 检测到问题内容，尝试提取命令..." -ForegroundColor Yellow
        }
        
        # 方法1: 查找常见的 PowerShell 命令
        $commonCmds = @('Get-Location', 'Get-ChildItem', 'Set-Location', 'Get-Process', 
                       'Get-Service', 'Get-Content', 'Select-String', 'Where-Object',
                       'pwd', 'ls', 'dir', 'cd', 'cat', 'type', 'findstr', 'grep',
                       'Write-Host', 'Write-Output', 'Get-Date', 'Test-Path')
        
        foreach ($pattern in $commonCmds) {
            if ($cmd -match [regex]::Escape($pattern)) {
                $match = [regex]::Match($cmd, "$([regex]::Escape($pattern))[^\u4e00-\u9fff\n]*")
                if ($match.Success) {
                    $extracted = $match.Value.Trim()
                    if ($extracted.Length -gt 0) {
                        if ($DEBUG) {
                            Write-Host "[DEBUG] 提取到命令: $extracted" -ForegroundColor Green
                        }
                        return $extracted
                    }
                }
            }
        }
        
        # 方法2: 提取所有以字母开头的单词序列（可能是命令）
        if ($cmd -match '([A-Za-z][A-Za-z0-9\-_\.]*\s+[^\u4e00-\u9fff\n?]*)') {
            $potentialCmd = $matches[1].Trim()
            # 移除末尾的问号
            $potentialCmd = $potentialCmd -replace '\?+$', ''
            if ($potentialCmd.Length -gt 0 -and $potentialCmd -notmatch '[\u4e00-\u9fff]') {
                if ($DEBUG) {
                    Write-Host "[DEBUG] 提取到潜在命令: $potentialCmd" -ForegroundColor Green
                }
                return $potentialCmd
            }
        }
        
        # 方法3: 如果包含问号，尝试提取问号之前的内容
        if ($cmd -match '^([^?]+)\?+') {
            $beforeQ = $matches[1].Trim()
            # 尝试从末尾提取命令
            if ($beforeQ -match '([A-Za-z][A-Za-z0-9\-_\.]*\s*.*?)$') {
                $extracted = $matches[1].Trim()
                if ($extracted.Length -gt 0 -and $extracted -notmatch '[\u4e00-\u9fff]') {
                    if ($DEBUG) {
                        Write-Host "[DEBUG] 从问号前提取: $extracted" -ForegroundColor Green
                    }
                    return $extracted
                }
            }
        }
    }
    
    # 最终清理
    $cmd = $cmd.Trim()
    if ($DEBUG) {
        Write-Host "[DEBUG] 最终命令: $cmd" -ForegroundColor Cyan
    }
    return $cmd
}

# 获取命令
function Get-AICommand {
    param([string]$query)
    
    # 更简洁的提示词
    $prompt = "将以下中文需求转换为一条 Windows PowerShell 命令，只输出命令，不要任何解释：

$query"

    $systemMsg = "你是一个命令转换助手。只输出命令，不要解释。"
    
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
        max_tokens = 128
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
            
            if ($DEBUG) {
                Write-Host "[DEBUG] 模型原始返回: $content" -ForegroundColor Magenta
            }
            
            # 尝试直接提取命令（在清理之前）
            $commonCmds = @('Get-Location', 'Get-ChildItem', 'Set-Location', 'Get-Process', 
                           'Get-Service', 'Get-Content', 'Select-String', 'Where-Object',
                           'pwd', 'ls', 'dir', 'cd', 'cat', 'type', 'findstr', 'grep')
            
            foreach ($cmdPattern in $commonCmds) {
                if ($content -match [regex]::Escape($cmdPattern)) {
                    $match = [regex]::Match($content, "$([regex]::Escape($cmdPattern))[^\u4e00-\u9fff\n]*")
                    if ($match.Success) {
                        $extracted = ($match.Value -split "`n")[0].Trim()
                        if ($extracted.Length -gt 0) {
                            return $extracted
                        }
                    }
                }
            }
            
            return $content
        } else {
            return "ERROR: empty model output"
        }
    } catch {
        if ($_.ErrorDetails.Message) {
            try {
                $errorObj = $_.ErrorDetails.Message | ConvertFrom-Json
                if ($errorObj.error.message) {
                    return "ERROR: $($errorObj.error.message)"
                }
            } catch {
                # 忽略 JSON 解析错误
            }
        }
        return "ERROR: $($_.Exception.Message)"
    }
}

# 主函数
if ($args.Count -lt 1) {
    Write-Host "用法: cc <中文需求>" -ForegroundColor Red
    exit 1
}

$userQuery = $args -join " "
$cmd = Get-AICommand $userQuery

if ($cmd -match "^ERROR:") {
    Write-Host $cmd -ForegroundColor Red
    exit 1
}

# 清理命令
$cmd = Sanitize-Command $cmd

if ([string]::IsNullOrWhiteSpace($cmd)) {
    Write-Host "错误: 模型返回了空命令" -ForegroundColor Red
    if ($DEBUG) {
        Write-Host "提示: 设置 `$DEBUG = `$true 查看详细调试信息" -ForegroundColor Yellow
    }
    exit 1
}

Write-Host ""
Write-Host "> AI 建议: $cmd" -ForegroundColor Green
Write-Host ""

$confirm = Read-Host "确认执行该命令吗？(y/Enter 执行, n 退出)"
if ([string]::IsNullOrWhiteSpace($confirm) -or $confirm -eq "y" -or $confirm -eq "yes") {
    Write-Host ""
    Write-Host "正在执行: $cmd" -ForegroundColor Yellow
    Write-Host ""
    Invoke-Expression $cmd
} else {
    Write-Host "已取消执行。"
}

