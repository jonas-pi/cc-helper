# cc 命令助手 PowerShell 脚本

# Ollama 配置
$OLLAMA_URL = "http://127.0.0.1:11434/v1"
$MODEL = "qwen2.5:1.5b"

# 调试模式（设置为 $true 可以看到原始返回）
# 如果遇到问题，可以临时设置为 $true 查看详细信息
$DEBUG = $false

# 如果命令全是问号，自动启用调试模式一次
if ($args.Count -gt 0) {
    $tempQuery = $args -join " "
    # 这里会在 Get-AICommand 中检测
}

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
    
    # 如果全是问号，直接返回错误
    if ($cmd -match '^\?+$') {
        if ($DEBUG) {
            Write-Host "[DEBUG] 检测到全是问号，可能是编码问题" -ForegroundColor Red
        }
        return ""
    }
    
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
            
            # 如果内容全是问号，可能是编码问题
            if ($content -match '^\?+$' -or ([regex]::Matches($content, '\?')).Count -gt ($content.Length * 0.5)) {
                if ($DEBUG) {
                    Write-Host "[DEBUG] 检测到问号过多（可能是编码问题），返回原始内容以便主函数处理" -ForegroundColor Yellow
                }
                # 返回问号内容，让主函数的智能推断处理
                return $content
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

# 尝试从模型获取命令
$cmd = Get-AICommand $userQuery

# 如果返回错误，显示错误并退出
if ($cmd -match "^ERROR:") {
    Write-Host $cmd -ForegroundColor Red
    exit 1
}

# 清理命令
$cmd = Sanitize-Command $cmd

# 如果清理后的命令无效（全是问号或为空），尝试智能推断
if ([string]::IsNullOrWhiteSpace($cmd) -or $cmd -match '^\?+$' -or ([regex]::Matches($cmd, '\?')).Count -gt 10) {
    if ($DEBUG) {
        Write-Host "[DEBUG] 命令无效，尝试根据原始查询智能推断..." -ForegroundColor Yellow
    }
    
    # 根据原始查询关键词推断命令
    $inferredCmd = ""
    if ($userQuery -match '目录|路径|位置|在哪') {
        $inferredCmd = "Get-Location"
    } elseif ($userQuery -match '文件.*列表|列出.*文件|查看.*文件|所有文件') {
        $inferredCmd = "Get-ChildItem"
    } elseif ($userQuery -match '进程|程序|运行中') {
        $inferredCmd = "Get-Process"
    } elseif ($userQuery -match '服务') {
        $inferredCmd = "Get-Service"
    } elseif ($userQuery -match '日期|时间|现在几点') {
        $inferredCmd = "Get-Date"
    } elseif ($userQuery -match '网络|IP|地址') {
        $inferredCmd = "Get-NetIPAddress"
    } elseif ($userQuery -match '端口|监听') {
        $inferredCmd = "Get-NetTCPConnection"
    } elseif ($userQuery -match '磁盘|空间|容量') {
        $inferredCmd = "Get-PSDrive"
    }
    
    if ($inferredCmd) {
        if ($DEBUG) {
            Write-Host "[DEBUG] 推断的命令: $inferredCmd" -ForegroundColor Green
        }
        $cmd = $inferredCmd
    }
}

if ([string]::IsNullOrWhiteSpace($cmd) -or $cmd -match '^\?+$') {
    Write-Host "错误: 模型返回了无效命令（可能是编码问题）" -ForegroundColor Red
    Write-Host ""
    Write-Host "提示: 请编辑 $env:USERPROFILE\cc.ps1" -ForegroundColor Yellow
    Write-Host "      将第 8 行的 `$DEBUG = `$false 改为 `$DEBUG = `$true" -ForegroundColor Yellow
    Write-Host "      然后重新运行以查看详细调试信息" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "或者，根据您的需求，可以尝试以下命令：" -ForegroundColor Cyan
    Write-Host "  - 查看当前目录: Get-Location 或 pwd" -ForegroundColor Cyan
    Write-Host "  - 列出文件: Get-ChildItem 或 ls" -ForegroundColor Cyan
    Write-Host "  - 查看进程: Get-Process" -ForegroundColor Cyan
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

