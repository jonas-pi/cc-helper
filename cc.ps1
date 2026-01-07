# cc 命令助手 PowerShell 脚本

# 版本信息
$VERSION = "0.2.3"

# 配置文件路径
$CONFIG_FILE = "$env:USERPROFILE\.cc_config.ps1"

# 默认配置
$OLLAMA_URL = "http://127.0.0.1:11434/v1"
$MODEL = "phi3.5"
$MODE = "work"  # work: 工作模式（只输出命令）, rest: 休息模式（可以聊天）
$API_TYPE = "ollama"  # ollama, openai, anthropic, custom
$API_KEY = ""  # API 密钥（如果需要）
$TARGET_SHELL = "powershell"  # powershell 或 cmd
$STREAM = $false  # true: 流式传输（逐字显示）, false: 一次性返回

# 加载配置文件
if (Test-Path $CONFIG_FILE) {
    try {
        . $CONFIG_FILE
        # 确保 MODE 变量被正确设置（如果配置文件加载失败，使用默认值）
        if (-not $MODE -or $MODE -eq "") {
            $MODE = "work"
        }
    } catch {
        # 如果配置文件加载失败，使用默认值
        Write-Host "警告: 配置文件加载失败，使用默认设置" -ForegroundColor Yellow
        $MODE = "work"
    }
}

# 自动检测目标 Shell（如果未配置）
if (-not $TARGET_SHELL -or $TARGET_SHELL -eq "") {
    # 检测父进程来判断运行环境
    $parentProcess = (Get-Process -Id $PID).Parent
    if ($parentProcess -and $parentProcess.ProcessName -match "cmd") {
        $TARGET_SHELL = "cmd"
    } else {
        $TARGET_SHELL = "powershell"
    }
}

# 检测控制台编码并选择合适的字符
$consoleEncoding = [Console]::OutputEncoding
$isGBK = ($consoleEncoding.CodePage -eq 936)

# 根据编码选择字符
if ($isGBK) {
    # GBK 编码：使用 ASCII 兼容字符
    $EMOJI_HELLO = "^_^"
    $BULLET = "-"
    $BULLET_CURRENT = "*"
} else {
    # UTF-8 编码：使用可爱的 Unicode 字符
    $EMOJI_HELLO = "(｡･ω･｡)"
    $BULLET = "•"
    $BULLET_CURRENT = "•"
}

# 检查并自动选择可用模型
function Check-And-Select-Model {
    # 如果不是 Ollama，跳过模型检查
    if ($script:API_TYPE -ne "ollama") {
        return $true
    }
    
    # 检查当前配置的模型是否存在
    $modelList = ollama list 2>$null
    if ($modelList -and $modelList -match [regex]::Escape($script:MODEL)) {
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

# 获取命令或回复
function Get-AICommand {
    param([string]$query)
    
    # 根据模式设置不同的提示词
    $prompt = ""
    $systemMsg = ""
    
    if ($MODE -eq "rest") {
        # 休息模式：可以聊天
        $shellType = if ($TARGET_SHELL -eq "cmd") { "CMD" } else { "PowerShell" }
        $prompt = @"
请用轻松友好的语气回复用户。可以聊天、解答问题、提供建议。

用户说：
$query

回复：
"@
        $systemMsg = "你是 cc，一个 AI 命令助手。性格：表面高冷实际上内心可爱热情的女孩子。你目前处于休息模式，可以和用户聊天交流。你的主要工作是帮助用户生成 $shellType 命令（工作模式），但现在是休息时间。回复时保持简洁、友好，偶尔展现出可爱的一面。"
    } else {
        # 工作模式：根据目标 Shell 生成不同提示词
        if ($TARGET_SHELL -eq "cmd") {
            $prompt = @"
判断以下输入是否是命令需求：
- 如果是命令需求（如"查看文件"、"列出目录"等），转换为一条 Windows CMD 命令并输出
- 如果不是命令需求（如"你好"、"谢谢"、"再见"等问候语或闲聊），只输出 "NOT_A_COMMAND"

只输出命令或 "NOT_A_COMMAND"，不要任何解释、不要 Markdown、不要代码块、不要额外文字。
注意：使用 CMD 语法，不是 PowerShell 语法。

输入：$query

输出：
"@
            $systemMsg = "You are cc, a Windows CMD command assistant. If the input is a command request (like 'list files', 'show directory'), output only the CMD command. If the input is NOT a command request (like greetings 'hello', 'thanks', casual chat), output ONLY 'NOT_A_COMMAND' with nothing else. Use CMD syntax, not PowerShell syntax."
        } else {
            $prompt = @"
判断以下输入是否是命令需求：
- 如果是命令需求（如"查看文件"、"列出目录"等），转换为一条 PowerShell 命令并输出
- 如果不是命令需求（如"你好"、"谢谢"、"再见"等问候语或闲聊），只输出 "NOT_A_COMMAND"

只输出命令或 "NOT_A_COMMAND"，不要任何解释、不要 Markdown、不要代码块、不要额外文字。

输入：$query

输出：
"@
            $systemMsg = "You are cc, a PowerShell command assistant. If the input is a command request (like 'list files', 'show directory'), output only the PowerShell command. If the input is NOT a command request (like greetings 'hello', 'thanks', casual chat), output ONLY 'NOT_A_COMMAND' with nothing else."
        }
    }
    
    # 构建 JSON
    # PowerShell 版本暂不支持流式传输解析，强制禁用
    $useStream = $false  # 未来版本将支持：($STREAM -and $MODE -eq "rest")
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
        stream = $useStream
    } | ConvertTo-Json -Depth 10

    # 调用 API
    try {
        $headers = @{
            "Content-Type" = "application/json"
        }
        
        # 根据 API 类型添加认证
        if ($API_KEY) {
            $headers["Authorization"] = "Bearer $API_KEY"
        } elseif ($API_TYPE -eq "ollama") {
            $headers["Authorization"] = "Bearer ollama"
        }
        
        $response = Invoke-RestMethod -Uri "$OLLAMA_URL/chat/completions" `
            -Method Post `
            -Headers $headers `
            -Body $jsonBody `
            -ErrorAction Stop

        if ($response.choices -and $response.choices.Count -gt 0 -and $response.choices[0].message.content) {
            $content = $response.choices[0].message.content
            
            # 确保 content 是字符串（关键修复）
            if ($content -is [array]) {
                # 如果是数组，取第一个元素或合并
                if ($content.Count -eq 1) {
                    $content = $content[0]
                } else {
                    $content = $content -join "`n"
                }
            }
            
            # 转换为字符串
            if ($content -isnot [string]) {
                $content = [string]$content
            }
            
            # 清理并返回
            $content = $content.Trim()
            if ([string]::IsNullOrWhiteSpace($content)) {
                return "ERROR: 模型返回空内容"
            }
            
            # 返回时确保是字符串
            return [string]$content
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
    Write-Host "$EMOJI_HELLO cc v$VERSION" -ForegroundColor Gray
    Write-Host ""
    
    # 显示 API 类型
    Write-Host "API 类型: " -NoNewline -ForegroundColor Gray
    Write-Host "$API_TYPE" -ForegroundColor Cyan
    
    # 显示当前模型
    Write-Host "当前模型: " -NoNewline -ForegroundColor Gray
    Write-Host "$MODEL" -ForegroundColor Green
    
    # 显示当前模式
    Write-Host "当前模式: " -NoNewline -ForegroundColor Gray
    if ($MODE -eq "rest") {
        Write-Host "休息模式" -NoNewline -ForegroundColor Magenta
        Write-Host " (可以聊天)" -ForegroundColor Gray
    } else {
        Write-Host "工作模式" -NoNewline -ForegroundColor Cyan
        Write-Host " (命令助手)" -ForegroundColor Gray
    }
    
    # 显示目标 Shell
    Write-Host "目标 Shell: " -NoNewline -ForegroundColor Gray
    if ($TARGET_SHELL -eq "cmd") {
        Write-Host "CMD" -ForegroundColor Yellow
    } else {
        Write-Host "PowerShell" -ForegroundColor Blue
    }
    
    # 显示流式传输状态
    Write-Host "流式传输: " -NoNewline -ForegroundColor Gray
    if ($STREAM) {
        Write-Host "开启" -NoNewline -ForegroundColor Green
        Write-Host " (逐字显示)" -ForegroundColor DarkGray
    } else {
        Write-Host "关闭" -NoNewline -ForegroundColor DarkGray
        Write-Host " (一次性显示)" -ForegroundColor DarkGray
    }
    
    Write-Host ""
    Write-Host "准备好了~ 有什么可以帮你的吗？" -ForegroundColor Gray
    Write-Host "提示: 使用 " -NoNewline -ForegroundColor DarkGray
    Write-Host "cc list" -NoNewline -ForegroundColor Green
    Write-Host " 查看模型列表" -ForegroundColor DarkGray
    exit 0
}

# 预设指令: list 列出模型
if ($firstArg -eq "list" -or $firstArg -eq "-list" -or $firstArg -eq "--list") {
    if ($API_TYPE -eq "ollama") {
        # Ollama: 列出本地安装的模型
        $modelList = ollama list 2>$null
        if (-not $modelList) {
            Write-Host "未找到已安装的模型" -ForegroundColor Yellow
            Write-Host "使用 " -NoNewline -ForegroundColor Gray
            Write-Host "cc -add" -NoNewline -ForegroundColor Green
            Write-Host " 安装新模型" -ForegroundColor Gray
            exit 0
        }
        
        $models = $modelList | Select-Object -Skip 1 | ForEach-Object {
            ($_ -split '\s+')[0]
        } | Where-Object { $_ -ne "" }
        
        if ($models.Count -eq 0) {
            Write-Host "未找到已安装的模型" -ForegroundColor Yellow
            Write-Host "使用 " -NoNewline -ForegroundColor Gray
            Write-Host "cc -add" -NoNewline -ForegroundColor Green
            Write-Host " 安装新模型" -ForegroundColor Gray
            exit 0
        }
        
        Write-Host "已安装的模型:" -ForegroundColor Gray
        Write-Host ""
        foreach ($model in $models) {
            if ($model -eq $MODEL) {
                Write-Host "  $BULLET_CURRENT " -NoNewline
                Write-Host "$model" -NoNewline -ForegroundColor Green
                Write-Host " (当前)" -ForegroundColor DarkGray
            } else {
                Write-Host "  $BULLET $model"
            }
        }
        Write-Host ""
        Write-Host "使用 " -NoNewline -ForegroundColor DarkGray
        Write-Host "cc -change" -NoNewline -ForegroundColor Green
        Write-Host " 切换模型" -ForegroundColor DarkGray
    } else {
        # 其他 API: 显示 API 信息
        Write-Host "当前 API 配置:" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  API 类型: " -NoNewline
        Write-Host "$API_TYPE" -ForegroundColor Cyan
        Write-Host "  API 地址: " -NoNewline
        Write-Host "$OLLAMA_URL" -ForegroundColor DarkGray
        Write-Host "  当前模型: " -NoNewline
        Write-Host "$MODEL" -ForegroundColor Green
        Write-Host ""
        Write-Host "使用 " -NoNewline -ForegroundColor DarkGray
        Write-Host "cc -config" -NoNewline -ForegroundColor Green
        Write-Host " 更改配置" -ForegroundColor DarkGray
    }
    exit 0
}

# 预设指令: testapi 测试 API 连接
if ($firstArg -eq "testapi" -or $firstArg -eq "test-api" -or $firstArg -eq "-test") {
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "            API 连接测试              " -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "当前配置:" -ForegroundColor Gray
    Write-Host "  API 类型: " -NoNewline; Write-Host "$API_TYPE" -ForegroundColor Cyan
    Write-Host "  API 地址: " -NoNewline; Write-Host "$OLLAMA_URL" -ForegroundColor Gray
    Write-Host "  模型名称: " -NoNewline; Write-Host "$MODEL" -ForegroundColor Green
    if ($API_KEY) {
        Write-Host "  API Key:  " -NoNewline; Write-Host "$($API_KEY.Substring(0, [Math]::Min(10, $API_KEY.Length)))..." -ForegroundColor Gray
    } else {
        Write-Host "  API Key:  " -NoNewline; Write-Host "(未设置)" -ForegroundColor Yellow
    }
    Write-Host ""
    
    Write-Host "正在测试连接..." -ForegroundColor Yellow
    Write-Host ""
    
    try {
        # 构建测试请求
        $testBody = @{
            model = $MODEL
            messages = @(
                @{
                    role = "user"
                    content = "hi"
                }
            )
            max_tokens = 5
        } | ConvertTo-Json -Depth 10
        
        # 构建 headers
        $headers = @{
            "Content-Type" = "application/json"
        }
        
        if ($API_KEY) {
            $headers["Authorization"] = "Bearer $API_KEY"
        } elseif ($API_TYPE -eq "ollama") {
            $headers["Authorization"] = "Bearer ollama"
        }
        
        # 发送测试请求
        $startTime = Get-Date
        $testResponse = Invoke-WebRequest -Uri "$OLLAMA_URL/chat/completions" `
            -Method Post `
            -Headers $headers `
            -Body $testBody `
            -TimeoutSec 30 `
            -ErrorAction Stop
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalMilliseconds
        
        # 解析响应
        $responseObj = $testResponse.Content | ConvertFrom-Json
        $content = $responseObj.choices[0].message.content
        
        if ($content) {
            Write-Host "✓ API 连接成功！" -ForegroundColor Green
            Write-Host ""
            Write-Host "响应时间: " -NoNewline -ForegroundColor Gray
            Write-Host "$([Math]::Round($duration))ms" -ForegroundColor Cyan
            Write-Host "模型响应: " -NoNewline -ForegroundColor Gray
            Write-Host "$content" -ForegroundColor Green
            Write-Host ""
            Write-Host "一切正常，可以使用 cc 了！" -ForegroundColor Green
        } else {
            Write-Host "⚠ API 连接成功，但响应异常" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "HTTP 状态码: " -NoNewline -ForegroundColor Gray
            Write-Host "$($testResponse.StatusCode)" -ForegroundColor Green
            Write-Host "响应时间: " -NoNewline -ForegroundColor Gray
            Write-Host "$([Math]::Round($duration))ms" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "原始响应:" -ForegroundColor Gray
            Write-Host ($testResponse.Content | ConvertFrom-Json | ConvertTo-Json -Depth 10)
        }
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errorMessage = $_.Exception.Message
        
        Write-Host "✗ API 连接失败" -ForegroundColor Red
        Write-Host ""
        Write-Host "HTTP 状态码: " -NoNewline -ForegroundColor Gray
        Write-Host "$statusCode" -ForegroundColor Red
        Write-Host ""
        Write-Host "可能的原因:" -ForegroundColor Yellow
        
        if ($statusCode -eq 401) {
            Write-Host "  1. API Key 无效或已过期" -ForegroundColor Red
            Write-Host "     - 检查 API Key 是否正确"
            Write-Host "     - 使用 " -NoNewline; Write-Host "cc -config" -NoNewline -ForegroundColor Green; Write-Host " 重新配置"
        } elseif ($statusCode -eq 404) {
            Write-Host "  1. API 地址错误或模型不存在" -ForegroundColor Red
            Write-Host "     - 检查 API_URL 配置"
            Write-Host "     - 检查模型名称: " -NoNewline; Write-Host "$MODEL" -ForegroundColor Green
            Write-Host "     - 使用 " -NoNewline; Write-Host "cc -config" -NoNewline -ForegroundColor Green; Write-Host " 重新配置"
        } elseif ($statusCode -eq 429) {
            Write-Host "  1. 请求过于频繁（限流）" -ForegroundColor Red
            Write-Host "     - 稍后再试"
        } elseif ($statusCode -eq 400) {
            Write-Host "  1. 请求参数错误" -ForegroundColor Red
            Write-Host "     - 模型名称可能不正确: " -NoNewline; Write-Host "$MODEL" -ForegroundColor Green
            Write-Host "     - 检查模型是否支持"
        } elseif (-not $statusCode -or $statusCode -eq 0) {
            Write-Host "  1. 网络连接失败" -ForegroundColor Red
            Write-Host "     - 检查网络连接"
            Write-Host "     - 检查 API 地址是否正确: " -NoNewline; Write-Host "$OLLAMA_URL" -ForegroundColor Gray
            if ($API_TYPE -eq "ollama") {
                Write-Host "     - 确认 Ollama 服务正在运行"
            }
        } else {
            Write-Host "  1. 未知错误" -ForegroundColor Red
            Write-Host "     - HTTP 状态码: $statusCode"
        }
        
        Write-Host ""
        Write-Host "错误详情:" -ForegroundColor Gray
        Write-Host "$errorMessage" -ForegroundColor DarkGray
        
        try {
            $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json | ConvertTo-Json -Depth 10
            Write-Host $errorBody -ForegroundColor DarkGray
        } catch {
            # 无法解析错误详情
        }
    }
    
    exit 0
}

# 预设指令: -w 工作模式
if ($firstArg -eq "-w" -or $firstArg -eq "work") {
    # 更新配置文件中的 MODE
    if (Test-Path $CONFIG_FILE) {
        $content = Get-Content $CONFIG_FILE -Raw
        
        # 使用更健壮的正则表达式匹配 MODE 设置（支持多行模式）
        if ($content -match '(?m)^\s*\$MODE\s*=\s*".*"') {
            # 如果找到 MODE 设置，替换它
            $content = $content -replace '(?m)^\s*\$MODE\s*=\s*".*"', '$MODE = "work"'
        } else {
            # 如果找不到，添加到文件末尾
            $content = $content.TrimEnd() + "`n`$MODE = `"work`""
        }
        
        $currentEncoding = [Console]::OutputEncoding
        if ($currentEncoding.CodePage -eq 936) {
            $saveEncoding = [System.Text.Encoding]::GetEncoding(936)
        } else {
            $saveEncoding = New-Object System.Text.UTF8Encoding $true
        }
        [System.IO.File]::WriteAllText($CONFIG_FILE, $content, $saveEncoding)
    } else {
        # 如果配置文件不存在，创建它
        '$MODE = "work"' | Out-File -FilePath $CONFIG_FILE -Encoding UTF8
    }
    
    # 立即更新当前会话的 MODE 变量
    $script:MODE = "work"
    
    Write-Host "已切换到工作模式" -ForegroundColor Cyan -NoNewline
    Write-Host " - 专注命令，高效执行" -ForegroundColor Gray
    exit 0
}

# 预设指令: -r 休息模式
if ($firstArg -eq "-r" -or $firstArg -eq "rest" -or $firstArg -eq "chat") {
    # 更新配置文件中的 MODE
    if (Test-Path $CONFIG_FILE) {
        $content = Get-Content $CONFIG_FILE -Raw
        
        # 使用更健壮的正则表达式匹配 MODE 设置（支持多行模式）
        if ($content -match '(?m)^\s*\$MODE\s*=\s*".*"') {
            # 如果找到 MODE 设置，替换它
            $content = $content -replace '(?m)^\s*\$MODE\s*=\s*".*"', '$MODE = "rest"'
        } else {
            # 如果找不到，添加到文件末尾
            $content = $content.TrimEnd() + "`n`$MODE = `"rest`""
        }
        
        $currentEncoding = [Console]::OutputEncoding
        if ($currentEncoding.CodePage -eq 936) {
            $saveEncoding = [System.Text.Encoding]::GetEncoding(936)
        } else {
            $saveEncoding = New-Object System.Text.UTF8Encoding $true
        }
        [System.IO.File]::WriteAllText($CONFIG_FILE, $content, $saveEncoding)
    } else {
        # 如果配置文件不存在，创建它
        '$MODE = "rest"' | Out-File -FilePath $CONFIG_FILE -Encoding UTF8
    }
    
    # 立即更新当前会话的 MODE 变量
    $script:MODE = "rest"
    
    Write-Host "已切换到休息模式" -ForegroundColor Magenta -NoNewline
    Write-Host " - 放松一下，聊聊天吧~" -ForegroundColor Gray
    exit 0
}

# 预设指令: -stream 切换流式传输
if ($firstArg -eq "-stream" -or $firstArg -eq "stream") {
    # 切换流式传输状态
    $newStream = -not $STREAM
    $statusText = if ($newStream) { "已开启流式传输" } else { "已关闭流式传输" }
    $descText = if ($newStream) { "响应将逐字显示（仅休息模式有效）" } else { "响应将一次性显示" }
    
    # 更新配置文件
    if (Test-Path $CONFIG_FILE) {
        $content = Get-Content $CONFIG_FILE -Raw
        if ($content -match '^\$STREAM = ') {
            $content = $content -replace '^\$STREAM = .*', "`$STREAM = `$$newStream"
        } else {
            $content += "`n`$STREAM = `$$newStream"
        }
        
        $currentEncoding = [Console]::OutputEncoding
        if ($currentEncoding.CodePage -eq 936) {
            $saveEncoding = [System.Text.Encoding]::GetEncoding(936)
        } else {
            $saveEncoding = New-Object System.Text.UTF8Encoding $true
        }
        [System.IO.File]::WriteAllText($CONFIG_FILE, $content, $saveEncoding)
    } else {
        "`$STREAM = `$$newStream" | Out-File -FilePath $CONFIG_FILE -Encoding UTF8
    }
    
    Write-Host "$statusText" -ForegroundColor Cyan -NoNewline
    Write-Host " - $descText" -ForegroundColor Gray
    Write-Host ""
    Write-Host "注意: 流式传输仅在休息模式 (cc -r) 下生效" -ForegroundColor DarkGray
    Write-Host "工作模式需要完整命令，不支持流式传输" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "提示: PowerShell 版本的流式传输功能正在开发中" -ForegroundColor Yellow
    Write-Host "      当前版本将在后台启用流式API，但显示仍为一次性输出" -ForegroundColor Yellow
    exit 0
}

# 预设指令: -fix 修复编码
if ($firstArg -eq "-fix" -or $firstArg -eq "fix" -or $firstArg -eq "-fix-encoding") {
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "            编码检测与修复              " -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    
    # 检测当前编码
    $currentEncoding = [Console]::OutputEncoding
    $currentCodePage = $currentEncoding.CodePage
    $encodingName = $currentEncoding.EncodingName
    
    Write-Host "当前系统信息:" -ForegroundColor Gray
    Write-Host "  控制台编码: " -NoNewline
    Write-Host "$encodingName" -ForegroundColor Green
    Write-Host "  CodePage: " -NoNewline
    Write-Host "$currentCodePage" -ForegroundColor Green
    Write-Host "  是否 GBK: " -NoNewline
    if ($currentCodePage -eq 936) {
        Write-Host "是 (简体中文)" -ForegroundColor Yellow
    } else {
        Write-Host "否 (UTF-8)" -ForegroundColor Green
    }
    Write-Host ""
    
    # 测试字符显示
    Write-Host "字符显示测试:" -ForegroundColor Gray
    if ($currentCodePage -eq 936) {
        Write-Host "  表情: ^_^" -ForegroundColor Green
        Write-Host "  列表: - 项目1 - 项目2" -ForegroundColor Green
        Write-Host "  当前: * 当前项" -ForegroundColor Green
    } else {
        Write-Host "  表情: (｡･ω･｡)" -ForegroundColor Green
        Write-Host "  列表: • 项目1 • 项目2" -ForegroundColor Green
        Write-Host "  当前: • 当前项" -ForegroundColor Green
    }
    Write-Host ""
    
    # 提供修复选项
    Write-Host "如果你看到乱码，可以尝试以下操作:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. 切换到 UTF-8 编码:" -ForegroundColor Cyan
    Write-Host "   [Console]::OutputEncoding = [System.Text.Encoding]::UTF8" -ForegroundColor Gray
    Write-Host "   chcp 65001" -ForegroundColor Gray
    Write-Host ""
    Write-Host "2. 切换到 GBK 编码 (简体中文):" -ForegroundColor Cyan
    Write-Host "   [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(936)" -ForegroundColor Gray
    Write-Host "   chcp 936" -ForegroundColor Gray
    Write-Host ""
    Write-Host "3. 重新安装 cc (自动检测编码):" -ForegroundColor Cyan
    Write-Host "   irm https://raw.githubusercontent.com/jonas-pi/cc-helper/main/install.ps1 | iex" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "是否要现在切换编码? [1=UTF-8, 2=GBK, n=取消]: " -NoNewline -ForegroundColor Yellow
    $choice = Read-Host
    
    switch ($choice) {
        "1" {
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            Write-Host ""
            Write-Host "✓ 已切换到 UTF-8 编码" -ForegroundColor Green
            Write-Host "测试: (｡･ω･｡) • 项目" -ForegroundColor Green
            Write-Host ""
            Write-Host "注意: 这个设置仅在当前会话有效" -ForegroundColor Yellow
            Write-Host "要永久生效，请在 PowerShell 配置文件中添加:" -ForegroundColor Gray
            Write-Host '  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8' -ForegroundColor Gray
        }
        "2" {
            [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(936)
            Write-Host ""
            Write-Host "✓ 已切换到 GBK 编码" -ForegroundColor Green
            Write-Host "测试: ^_^ - 项目" -ForegroundColor Green
            Write-Host ""
            Write-Host "注意: 这个设置仅在当前会话有效" -ForegroundColor Yellow
            Write-Host "要永久生效，请在 PowerShell 配置文件中添加:" -ForegroundColor Gray
            Write-Host '  [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(936)' -ForegroundColor Gray
        }
        default {
            Write-Host "已取消" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
    Write-Host "是否要强制更新 cc 到最新版本?" -ForegroundColor Gray
    Write-Host "(编码修复后建议更新以确保所有功能正常)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "[y/n] (默认: n): " -NoNewline -ForegroundColor Yellow
    $updateChoice = Read-Host
    
    if ($updateChoice -eq "y" -or $updateChoice -eq "Y") {
        Write-Host ""
        Write-Host "正在强制更新..." -ForegroundColor Cyan
        
        try {
            # 下载最新版本
            $updateUrl = "https://raw.githubusercontent.com/jonas-pi/cc-helper/main/cc.ps1?t=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
            $outputPath = "$env:USERPROFILE\cc.ps1"
            
            # 备份当前版本
            if (Test-Path $outputPath) {
                Copy-Item $outputPath "$outputPath.backup" -Force | Out-Null
            }
            
            # 下载内容并始终使用 UTF-8 with BOM 保存
            $webClient = New-Object System.Net.WebClient
            $webClient.Encoding = [System.Text.Encoding]::UTF8
            $content = $webClient.DownloadString($updateUrl)
            $saveEncoding = New-Object System.Text.UTF8Encoding $true
            [System.IO.File]::WriteAllText($outputPath, $content, $saveEncoding)
            
            Write-Host ""
            Write-Host "✓ 更新完成！" -ForegroundColor Green
            Write-Host ""
            Write-Host "现在运行: " -NoNewline -ForegroundColor Gray
            Write-Host "cc hello" -ForegroundColor Green
        } catch {
            Write-Host ""
            Write-Host "✗ 更新失败" -ForegroundColor Red
            Write-Host "请手动运行: " -NoNewline -ForegroundColor Gray
            Write-Host "cc -u" -ForegroundColor Green
        }
    } else {
        Write-Host "已跳过更新" -ForegroundColor Gray
    }
    
    exit 0
}

# 预设指令: -shell 切换目标 Shell
if ($firstArg -eq "-shell" -or $firstArg -eq "shell") {
    Write-Host "当前目标 Shell: " -NoNewline -ForegroundColor Gray
    if ($TARGET_SHELL -eq "cmd") {
        Write-Host "CMD" -ForegroundColor Yellow
    } else {
        Write-Host "PowerShell" -ForegroundColor Blue
    }
    Write-Host ""
    Write-Host "切换到:" -ForegroundColor Yellow
    Write-Host "  1. PowerShell" -ForegroundColor Blue
    Write-Host "  2. CMD" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "请选择 [1/2]: " -ForegroundColor Yellow -NoNewline
    $choice = Read-Host
    
    $newShell = switch ($choice) {
        "1" { "powershell" }
        "2" { "cmd" }
        default { $TARGET_SHELL }
    }
    
    if ($newShell -ne $TARGET_SHELL) {
        $scriptPath = "$env:USERPROFILE\cc.ps1"
        $content = Get-Content $scriptPath -Raw
        $content = $content -replace '^\$TARGET_SHELL = ".*"', "`$TARGET_SHELL = `"$newShell`""
        
        $currentEncoding = [Console]::OutputEncoding
        if ($currentEncoding.CodePage -eq 936) {
            $saveEncoding = [System.Text.Encoding]::GetEncoding(936)
        } else {
            $saveEncoding = New-Object System.Text.UTF8Encoding $true
        }
        [System.IO.File]::WriteAllText($scriptPath, $content, $saveEncoding)
        
        $shellName = if ($newShell -eq "cmd") { "CMD" } else { "PowerShell" }
        Write-Host "✓ 已切换目标 Shell 到: " -NoNewline -ForegroundColor Green
        Write-Host "$shellName" -ForegroundColor $(if ($newShell -eq "cmd") { "Yellow" } else { "Blue" })
    } else {
        Write-Host "未更改" -ForegroundColor Gray
    }
    exit 0
}

# 预设指令: -u 更新（不依赖模型）
if ($firstArg -eq "-u" -or $firstArg -eq "update" -or $firstArg -eq "--update") {
    Write-Host "正在检查更新..." -ForegroundColor Cyan
    
    try {
        # 获取远程版本号
        $webClient = New-Object System.Net.WebClient
        $webClient.Encoding = [System.Text.Encoding]::UTF8
        $remoteVersion = $webClient.DownloadString("https://raw.githubusercontent.com/jonas-pi/cc-helper/main/VERSION").Trim()
        
        Write-Host "当前版本: " -NoNewline -ForegroundColor Gray
        Write-Host "$VERSION" -ForegroundColor Yellow
        Write-Host "最新版本: " -NoNewline -ForegroundColor Gray
        Write-Host "$remoteVersion" -ForegroundColor Green
        Write-Host ""
        
        # 版本比较
        if ($VERSION -eq $remoteVersion) {
            Write-Host "✓ 已是最新版本" -ForegroundColor Green
            exit 0
        }
        
        # 获取更新日志
        Write-Host "更新内容:" -ForegroundColor Magenta
        $changelog = $webClient.DownloadString("https://raw.githubusercontent.com/jonas-pi/cc-helper/main/CHANGELOG.md")
        $changelogLines = $changelog -split "`n"
        $inCurrentVersion = $false
        foreach ($line in $changelogLines) {
            if ($line -match "## v$remoteVersion") {
                $inCurrentVersion = $true
                continue
            }
            if ($inCurrentVersion) {
                # 遇到分隔符或下一个版本标题时停止
                if ($line -match "^---$" -or ($line -match "^## v" -and $line -notmatch "## v$remoteVersion")) {
                    break
                }
                Write-Host $line
            }
        }
        Write-Host ""
        
        $confirm = Read-Host "是否更新到 v${remoteVersion}? [y/n]"
        if ($confirm -ne "y" -and $confirm -ne "Y") {
            Write-Host "已取消更新" -ForegroundColor Gray
            exit 0
        }
        
        Write-Host "正在下载最新版本..." -ForegroundColor Gray
        
        $url = "https://raw.githubusercontent.com/jonas-pi/cc-helper/main/cc.ps1"
        $outputPath = "$env:USERPROFILE\cc.ps1"
        
        # 备份当前文件
        if (Test-Path $outputPath) {
            Copy-Item $outputPath "$outputPath.backup" -Force | Out-Null
        }

        # 下载主脚本
        $content = $webClient.DownloadString($url)
        
        # 主脚本始终使用 UTF-8 with BOM 保存（PowerShell 能正确识别）
        $saveEncoding = New-Object System.Text.UTF8Encoding $true
        [System.IO.File]::WriteAllText($outputPath, $content, $saveEncoding)
        Write-Host "✓ 主脚本更新完成" -ForegroundColor Green
        
        # 更新 Tab 补全脚本
        try {
            $completionFile = "$env:USERPROFILE\.cc-completion.ps1"
            $completionContent = $webClient.DownloadString("https://raw.githubusercontent.com/jonas-pi/cc-helper/main/cc-completion.ps1")
            [System.IO.File]::WriteAllText($completionFile, $completionContent, [System.Text.Encoding]::UTF8)
            Write-Host "✓ Tab 补全脚本已更新" -ForegroundColor Green
            
            # 检查是否已添加到 Profile
            if (!(Test-Path $PROFILE)) {
                New-Item -ItemType File -Path $PROFILE -Force | Out-Null
            }
            $profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
            if (!$profileContent -or !($profileContent -match "\.cc-completion\.ps1")) {
                Add-Content -Path $PROFILE -Value "`n# cc 命令补全"
                Add-Content -Path $PROFILE -Value "if (Test-Path `"$completionFile`") { . `"$completionFile`" }"
                Write-Host "  ✓ 已添加补全到 Profile（需要重启 PowerShell 生效）" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "⚠ Tab 补全更新失败（不影响使用）" -ForegroundColor Yellow
        }
        
        Write-Host ""
        Write-Host "现在运行: " -NoNewline -ForegroundColor Gray
        Write-Host "cc hello" -ForegroundColor Green
    } catch {
        Write-Host "无法获取版本信息" -ForegroundColor Red
        $confirm = Read-Host "是否继续更新? [y/n]"
        if ($confirm -ne "y" -and $confirm -ne "Y") {
            exit 0
        }
        
        Write-Host "正在下载..." -ForegroundColor Gray
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.Encoding = [System.Text.Encoding]::UTF8
            $url = "https://raw.githubusercontent.com/jonas-pi/cc-helper/main/cc.ps1"
            $outputPath = "$env:USERPROFILE\cc.ps1"
            
            if (Test-Path $outputPath) {
                Copy-Item $outputPath "$outputPath.backup" -Force | Out-Null
            }
            
            # 下载内容并始终使用 UTF-8 with BOM 保存
            $content = $webClient.DownloadString($url)
            $saveEncoding = New-Object System.Text.UTF8Encoding $true
            [System.IO.File]::WriteAllText($outputPath, $content, $saveEncoding)
            Write-Host "✓ 更新完成" -ForegroundColor Green
        } catch {
            Write-Host "✗ 更新失败: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    }
    exit 0
}

# 预设指令: -change 切换模型
if ($firstArg -eq "-change" -or $firstArg -eq "change") {
    Write-Host "当前配置:" -ForegroundColor Cyan
    Write-Host "  API 类型: " -NoNewline; Write-Host "$API_TYPE" -ForegroundColor Cyan
    Write-Host "  当前模型: " -NoNewline; Write-Host "$MODEL" -ForegroundColor Green
    Write-Host ""
    
    if ($API_TYPE -eq "ollama") {
        # Ollama: 列出本地已下载的模型
        $modelList = ollama list 2>$null
        if (-not $modelList) {
            Write-Host "ERROR: 未找到已安装的模型" -ForegroundColor Red
            exit 1
        }
        
        $models = $modelList | Select-Object -Skip 1 | ForEach-Object {
            ($_ -split '\s+')[0]
        } | Where-Object { $_ -ne "" }
        
        if ($models.Count -eq 0) {
            Write-Host "ERROR: 未找到已安装的模型" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "已安装的模型:" -ForegroundColor Gray
        for ($i = 0; $i -lt $models.Count; $i++) {
            if ($models[$i] -eq $MODEL) {
                Write-Host "  $($i + 1). " -NoNewline
                Write-Host "$($models[$i])" -ForegroundColor Green -NoNewline
                Write-Host " (当前)"
            } else {
                Write-Host "  $($i + 1). $($models[$i])"
            }
        }
    
        Write-Host ""
        Write-Host "请选择模型 (序号): " -ForegroundColor Yellow -NoNewline
        $choice = Read-Host
        
        $index = [int]$choice - 1
        if ($index -lt 0 -or $index -ge $models.Count) {
            Write-Host "无效选择" -ForegroundColor Red
            exit 1
        }
        
        $selected = $models[$index]
    } else {
        # 云端 API: 提供常见模型或手动输入
        Write-Host "常见模型:" -ForegroundColor Gray
        switch ($API_TYPE) {
            "openai" {
                Write-Host "  1. gpt-3.5-turbo"
                Write-Host "  2. gpt-4"
                Write-Host "  3. gpt-4-turbo"
                Write-Host "  4. gpt-4o"
                Write-Host "  5. gpt-4o-mini"
            }
            "anthropic" {
                Write-Host "  1. claude-3-haiku-20240307"
                Write-Host "  2. claude-3-sonnet-20240229"
                Write-Host "  3. claude-3-opus-20240229"
                Write-Host "  4. claude-3-5-sonnet-20241022"
            }
            "deepseek" {
                Write-Host "  1. deepseek-chat"
                Write-Host "  2. deepseek-coder"
            }
            "qwen" {
                Write-Host "  1. qwen-plus"
                Write-Host "  2. qwen-turbo"
                Write-Host "  3. qwen-max"
            }
            "doubao" {
                Write-Host "  1. doubao-pro-32k"
                Write-Host "  2. doubao-lite-32k"
            }
            default {
                Write-Host "  (自定义 API)" -ForegroundColor DarkGray
            }
        }
        Write-Host "  0. 手动输入模型名称"
        Write-Host ""
        Write-Host "请选择 (序号) 或直接输入模型名称: " -ForegroundColor Yellow -NoNewline
        $choice = Read-Host
        
        $selected = ""
        switch ($API_TYPE) {
            "openai" {
                switch ($choice) {
                    "1" { $selected = "gpt-3.5-turbo" }
                    "2" { $selected = "gpt-4" }
                    "3" { $selected = "gpt-4-turbo" }
                    "4" { $selected = "gpt-4o" }
                    "5" { $selected = "gpt-4o-mini" }
                    default {
                        if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) {
                            $selected = Read-Host "输入模型名称"
                        } else {
                            $selected = $choice
                        }
                    }
                }
            }
            "anthropic" {
                switch ($choice) {
                    "1" { $selected = "claude-3-haiku-20240307" }
                    "2" { $selected = "claude-3-sonnet-20240229" }
                    "3" { $selected = "claude-3-opus-20240229" }
                    "4" { $selected = "claude-3-5-sonnet-20241022" }
                    default {
                        if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) {
                            $selected = Read-Host "输入模型名称"
                        } else {
                            $selected = $choice
                        }
                    }
                }
            }
            "deepseek" {
                switch ($choice) {
                    "1" { $selected = "deepseek-chat" }
                    "2" { $selected = "deepseek-coder" }
                    default {
                        if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) {
                            $selected = Read-Host "输入模型名称"
                        } else {
                            $selected = $choice
                        }
                    }
                }
            }
            "qwen" {
                switch ($choice) {
                    "1" { $selected = "qwen-plus" }
                    "2" { $selected = "qwen-turbo" }
                    "3" { $selected = "qwen-max" }
                    default {
                        if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) {
                            $selected = Read-Host "输入模型名称"
                        } else {
                            $selected = $choice
                        }
                    }
                }
            }
            "doubao" {
                switch ($choice) {
                    "1" { $selected = "doubao-pro-32k" }
                    "2" { $selected = "doubao-lite-32k" }
                    default {
                        if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) {
                            $selected = Read-Host "输入模型名称"
                        } else {
                            $selected = $choice
                        }
                    }
                }
            }
            default {
                # 自定义 API，直接输入
                if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) {
                    $selected = Read-Host "输入模型名称"
                } else {
                    $selected = $choice
                }
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($selected)) {
            Write-Host "无效输入" -ForegroundColor Red
            exit 1
        }
    }
    
    # 更新配置文件
    if (Test-Path $CONFIG_FILE) {
        $content = Get-Content $CONFIG_FILE -Raw
        if ($content -match '(?m)^\s*\$MODEL\s*=') {
            $content = $content -replace '(?m)^\s*\$MODEL\s*=\s*".*"', "`$MODEL = `"$selected`""
        } else {
            $content = $content.TrimEnd() + "`n`$MODEL = `"$selected`""
        }
        
        $currentEncoding = [Console]::OutputEncoding
        if ($currentEncoding.CodePage -eq 936) {
            $saveEncoding = [System.Text.Encoding]::GetEncoding(936)
        } else {
            $saveEncoding = New-Object System.Text.UTF8Encoding $true
        }
        [System.IO.File]::WriteAllText($CONFIG_FILE, $content, $saveEncoding)
    } else {
        "`$MODEL = `"$selected`"" | Out-File -FilePath $CONFIG_FILE -Encoding UTF8
    }
    
    Write-Host ""
    Write-Host "✓ 已切换到: $selected" -ForegroundColor Green
    Write-Host ""
    Write-Host "提示: 使用 " -NoNewline -ForegroundColor Gray
    Write-Host "cc testapi" -NoNewline -ForegroundColor Green
    Write-Host " 测试新模型连接" -ForegroundColor Gray
    exit 0
}

# 预设指令: -add 安装新模型
if ($firstArg -eq "-add" -or $firstArg -eq "add") {
    Write-Host "推荐模型:" -ForegroundColor Gray
    Write-Host "  1. phi3.5        - 微软模型，PS最佳 (2.2GB)"
    Write-Host "  2. llama3.2:1b   - Meta轻量 (1.2GB)"
    Write-Host "  3. llama3.2:3b   - Meta平衡 (2GB)"
    Write-Host "  4. qwen2.5:0.5b  - 超轻量 (400MB)"
    Write-Host "  5. qwen2.5:1.5b  - 轻量推荐 (1GB)"
    Write-Host "  6. qwen2.5:3b    - 平衡之选 (2GB)"
    Write-Host "  7. qwen2.5:7b    - 高性能 (4.7GB)"
    Write-Host "  8. 自定义模型名"
    Write-Host ""
    Write-Host "请选择 (序号或输入模型名): " -ForegroundColor Yellow -NoNewline
    $choice = Read-Host
    
    $model = switch ($choice) {
        "1" { "phi3.5" }
        "2" { "llama3.2:1b" }
        "3" { "llama3.2:3b" }
        "4" { "qwen2.5:0.5b" }
        "5" { "qwen2.5:1.5b" }
        "6" { "qwen2.5:3b" }
        "7" { "qwen2.5:7b" }
        "8" {
            Write-Host "输入模型名: " -ForegroundColor Yellow -NoNewline
            Read-Host
        }
        default { $choice }
    }
    
    if ([string]::IsNullOrWhiteSpace($model)) {
        Write-Host "无效输入" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "正在安装 $model..." -ForegroundColor Gray
    ollama pull $model
    if ($LASTEXITCODE -eq 0) {
        Write-Host "安装完成" -ForegroundColor Gray
        Write-Host "是否切换到此模型? [y/n] " -ForegroundColor Yellow -NoNewline
        $switch = Read-Host
        if ($switch -eq "y" -or $switch -eq "Y" -or [string]::IsNullOrWhiteSpace($switch)) {
            $scriptPath = "$env:USERPROFILE\cc.ps1"
            $content = Get-Content $scriptPath -Raw
            $content = $content -replace '^\$MODEL = ".*"', "`$MODEL = `"$model`""
            
            $currentEncoding = [Console]::OutputEncoding
            if ($currentEncoding.CodePage -eq 936) {
                $saveEncoding = [System.Text.Encoding]::GetEncoding(936)
            } else {
                $saveEncoding = New-Object System.Text.UTF8Encoding $true
            }
            [System.IO.File]::WriteAllText($scriptPath, $content, $saveEncoding)
            
            Write-Host "已切换到: $model" -ForegroundColor Gray
        }
    } else {
        Write-Host "安装失败" -ForegroundColor Red
        exit 1
    }
    exit 0
}

# 预设指令: -config 配置 API
if ($firstArg -eq "-config" -or $firstArg -eq "config") {
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "          CC API 配置 - 成长空间          " -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "当前配置:" -ForegroundColor White
    Write-Host "  API 类型: " -NoNewline; Write-Host $API_TYPE -ForegroundColor Green
    Write-Host "  API 地址: " -NoNewline; Write-Host $OLLAMA_URL -ForegroundColor Gray
    Write-Host "  模型: " -NoNewline; Write-Host $MODEL -ForegroundColor Gray
    if ($API_KEY) {
        Write-Host "  API Key: " -NoNewline; Write-Host "$($API_KEY.Substring(0, [Math]::Min(10, $API_KEY.Length)))..." -ForegroundColor Gray
    } else {
        Write-Host "  API Key: " -NoNewline; Write-Host "(未设置)" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "可选 API 类型:" -ForegroundColor Magenta
    Write-Host "  1. " -NoNewline; Write-Host "ollama" -ForegroundColor Green -NoNewline; Write-Host "       - 本地 Ollama（默认，免费）"
    Write-Host "  2. " -NoNewline; Write-Host "openai" -ForegroundColor Yellow -NoNewline; Write-Host "       - OpenAI GPT 系列"
    Write-Host "  3. " -NoNewline; Write-Host "anthropic" -ForegroundColor Magenta -NoNewline; Write-Host "    - Anthropic Claude 系列"
    Write-Host "  4. " -NoNewline; Write-Host "deepseek" -ForegroundColor Blue -NoNewline; Write-Host "     - DeepSeek（国内，高性价比）"
    Write-Host "  5. " -NoNewline; Write-Host "doubao" -ForegroundColor Cyan -NoNewline; Write-Host "       - 豆包/火山方舟（字节跳动）"
    Write-Host "  6. " -NoNewline; Write-Host "qwen" -ForegroundColor Green -NoNewline; Write-Host "         - 通义千问/阿里云百炼"
    Write-Host "  7. " -NoNewline; Write-Host "custom" -ForegroundColor Cyan -NoNewline; Write-Host "       - 自定义兼容 OpenAI API 的服务"
    Write-Host ""
    Write-Host "选择 API 类型 (1-7，直接回车保持当前): " -ForegroundColor Yellow -NoNewline
    $apiChoice = Read-Host
    
    switch ($apiChoice) {
        "1" {
            $API_TYPE = "ollama"
            Write-Host "Ollama 地址 [http://127.0.0.1:11434/v1]: " -ForegroundColor Yellow -NoNewline
            $url = Read-Host
            $OLLAMA_URL = if ($url) { $url } else { "http://127.0.0.1:11434/v1" }
            $API_KEY = ""
            Write-Host "模型名称 [phi3.5]: " -ForegroundColor Yellow -NoNewline
            $model = Read-Host
            $MODEL = if ($model) { $model } else { "phi3.5" }
        }
        "2" {
            $API_TYPE = "openai"
            $OLLAMA_URL = "https://api.openai.com/v1"
            Write-Host "OpenAI API Key: " -ForegroundColor Yellow -NoNewline
            $API_KEY = Read-Host
            Write-Host "模型名称 [gpt-3.5-turbo]: " -ForegroundColor Yellow -NoNewline
            $model = Read-Host
            $MODEL = if ($model) { $model } else { "gpt-3.5-turbo" }
        }
        "3" {
            $API_TYPE = "anthropic"
            $OLLAMA_URL = "https://api.anthropic.com/v1"
            Write-Host "Anthropic API Key: " -ForegroundColor Yellow -NoNewline
            $API_KEY = Read-Host
            Write-Host "模型名称 [claude-3-haiku-20240307]: " -ForegroundColor Yellow -NoNewline
            $model = Read-Host
            $MODEL = if ($model) { $model } else { "claude-3-haiku-20240307" }
        }
        "4" {
            $API_TYPE = "deepseek"
            $OLLAMA_URL = "https://api.deepseek.com"
            Write-Host "DeepSeek API Key: " -ForegroundColor Yellow -NoNewline
            $API_KEY = Read-Host
            Write-Host "模型名称 [deepseek-chat]: " -ForegroundColor Yellow -NoNewline
            $model = Read-Host
            $MODEL = if ($model) { $model } else { "deepseek-chat" }
        }
        "5" {
            $API_TYPE = "doubao"
            Write-Host "火山方舟 API 地址 [https://ark.cn-beijing.volces.com/api/v3]: " -ForegroundColor Yellow -NoNewline
            $url = Read-Host
            $OLLAMA_URL = if ($url) { $url } else { "https://ark.cn-beijing.volces.com/api/v3" }
            Write-Host "火山方舟 API Key: " -ForegroundColor Yellow -NoNewline
            $API_KEY = Read-Host
            Write-Host "模型名称 (如 doubao-pro-32k): " -ForegroundColor Yellow -NoNewline
            $MODEL = Read-Host
        }
        "6" {
            $API_TYPE = "qwen"
            $OLLAMA_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
            Write-Host "阿里云百炼 API Key: " -ForegroundColor Yellow -NoNewline
            $API_KEY = Read-Host
            Write-Host "模型名称 [qwen-plus]: " -ForegroundColor Yellow -NoNewline
            $model = Read-Host
            $MODEL = if ($model) { $model } else { "qwen-plus" }
        }
        "7" {
            $API_TYPE = "custom"
            Write-Host "API 地址: " -ForegroundColor Yellow -NoNewline
            $OLLAMA_URL = Read-Host
            Write-Host "API Key (可选，直接回车跳过): " -ForegroundColor Yellow -NoNewline
            $API_KEY = Read-Host
            Write-Host "模型名称: " -ForegroundColor Yellow -NoNewline
            $MODEL = Read-Host
        }
        "" {
            Write-Host "保持当前配置" -ForegroundColor Gray
            exit 0
        }
        default {
            Write-Host "无效选择" -ForegroundColor Red
            exit 1
        }
    }
    
    # 保存配置
    $configContent = @"
# CC 配置文件
# 由 cc -config 自动生成

`$API_TYPE = "$API_TYPE"
`$OLLAMA_URL = "$OLLAMA_URL"
`$MODEL = "$MODEL"
`$API_KEY = "$API_KEY"
`$MODE = "$MODE"
`$TARGET_SHELL = "$TARGET_SHELL"
"@
    
    $configContent | Out-File -FilePath $CONFIG_FILE -Encoding UTF8
    
    Write-Host ""
    Write-Host "✓ 配置已保存到 $CONFIG_FILE" -ForegroundColor Green
    
    # 测试 API 连接
    Write-Host ""
    Write-Host "正在测试 API 连接..." -ForegroundColor Yellow
    
    try {
        $headers = @{
            "Content-Type" = "application/json"
        }
        
        if ($API_KEY) {
            $headers["Authorization"] = "Bearer $API_KEY"
        } elseif ($API_TYPE -eq "ollama") {
            $headers["Authorization"] = "Bearer ollama"
        }
        
        $testBody = @{
            model = $MODEL
            messages = @(
                @{
                    role = "user"
                    content = "hi"
                }
            )
            max_tokens = 5
        } | ConvertTo-Json -Depth 10
        
        $testResponse = Invoke-RestMethod -Uri "$OLLAMA_URL/chat/completions" `
            -Method Post `
            -Headers $headers `
            -Body $testBody `
            -TimeoutSec 10 `
            -ErrorAction Stop
        
        if ($testResponse.choices -and $testResponse.choices.Count -gt 0) {
            Write-Host "✓ API 连接成功！模型响应正常" -ForegroundColor Green
        } else {
            Write-Host "⚠ API 连接成功，但模型响应异常" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "✗ API 连接失败: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "请检查:" -ForegroundColor Yellow
        Write-Host "  1. API Key 是否正确" -ForegroundColor Gray
        Write-Host "  2. 模型名称是否正确" -ForegroundColor Gray
        Write-Host "  3. 网络连接是否正常" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "现在运行: " -NoNewline; Write-Host "cc hello" -ForegroundColor Green
    exit 0
}

# 预设指令: -del 删除模型
if ($firstArg -eq "-del" -or $firstArg -eq "delete" -or $firstArg -eq "rm") {
    $modelList = ollama list 2>$null
    if (-not $modelList) {
        Write-Host "ERROR: 未找到已安装的模型" -ForegroundColor Red
        exit 1
    }
    
    $models = $modelList | Select-Object -Skip 1 | ForEach-Object {
        ($_ -split '\s+')[0]
    } | Where-Object { $_ -ne "" }
    
    if ($models.Count -eq 0) {
        Write-Host "ERROR: 未找到已安装的模型" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "已安装的模型:" -ForegroundColor Gray
    for ($i = 0; $i -lt $models.Count; $i++) {
        if ($models[$i] -eq $MODEL) {
            Write-Host "  $($i + 1). " -NoNewline
            Write-Host "$($models[$i])" -ForegroundColor Green -NoNewline
            Write-Host " (当前使用)"
        } else {
            Write-Host "  $($i + 1). $($models[$i])"
        }
    }
    
    Write-Host ""
    Write-Host "请选择要删除的模型 (序号，多个用空格分隔): " -ForegroundColor Yellow -NoNewline
    $choices = Read-Host
    
    $numbers = $choices -split '\s+' | Where-Object { $_ -match '^\d+$' }
    foreach ($num in $numbers) {
        $index = [int]$num - 1
        if ($index -lt 0 -or $index -ge $models.Count) {
            Write-Host "无效序号: $num" -ForegroundColor Red
            continue
        }
        
        $selected = $models[$index]
        
        if ($selected -eq $MODEL) {
            Write-Host "警告: $selected 是当前使用的模型" -ForegroundColor Yellow
            Write-Host "确认删除? [y/n] " -ForegroundColor Yellow -NoNewline
            $confirm = Read-Host
            if ($confirm -ne "y" -and $confirm -ne "Y") {
                Write-Host "跳过 $selected" -ForegroundColor Gray
                continue
            }
        }
        
        Write-Host "正在删除 $selected..." -ForegroundColor Gray
        ollama rm $selected 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "已删除 $selected" -ForegroundColor Gray
        } else {
            Write-Host "删除失败: $selected" -ForegroundColor Red
        }
    }
    exit 0
}

# 帮助信息
if ($args.Count -lt 1 -or $firstArg -eq "-h" -or $firstArg -eq "--help" -or $firstArg -eq "-help" -or $firstArg -eq "help") {
    if ($isGBK) {
        # GBK 编码：使用简单边框
        Write-Host "============================================" -ForegroundColor Cyan
        Write-Host "         CC 命令助手 - 使用指南          " -ForegroundColor Cyan
        Write-Host "============================================" -ForegroundColor Cyan
    } else {
        # UTF-8 编码：使用漂亮的边框
        Write-Host "╔════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║         CC 命令助手 - 使用指南          ║" -ForegroundColor Cyan
        Write-Host "╚════════════════════════════════════════════╝" -ForegroundColor Cyan
    }
    Write-Host ""
    Write-Host "cc hello" -NoNewline -ForegroundColor Green; Write-Host "       " -NoNewline; Write-Host "cc list" -NoNewline -ForegroundColor Green; Write-Host "        " -NoNewline; Write-Host "cc testapi" -ForegroundColor Green
    Write-Host "cc -w" -NoNewline -ForegroundColor Green; Write-Host "          " -NoNewline; Write-Host "cc -r" -NoNewline -ForegroundColor Green; Write-Host "          " -NoNewline; Write-Host "cc -stream" -ForegroundColor Green
    Write-Host "cc -config" -NoNewline -ForegroundColor Green; Write-Host "     " -NoNewline; Write-Host "cc -change" -NoNewline -ForegroundColor Green; Write-Host "     " -NoNewline; Write-Host "cc -add" -ForegroundColor Green
    Write-Host "cc -del" -NoNewline -ForegroundColor Green; Write-Host "        " -NoNewline; Write-Host "cc -shell" -NoNewline -ForegroundColor Green; Write-Host "      " -NoNewline; Write-Host "cc -fix" -ForegroundColor Green
    Write-Host "cc -u" -NoNewline -ForegroundColor Green; Write-Host "          " -NoNewline; Write-Host "cc -h" -ForegroundColor Green
    exit 0
}

# 获取用户输入（确保正确处理参数）
$userQuery = if ($args.Count -eq 1 -and $args[0] -is [string]) {
    $args[0]
} elseif ($args.Count -gt 0) {
    $args -join " "
} else {
    ""
}

# 检查并选择可用模型
if (-not (Check-And-Select-Model)) {
    exit 1
}

$cmd = Get-AICommand $userQuery

if ($cmd -match "^ERROR:") {
    Write-Host $cmd -ForegroundColor Red
    exit 1
}

# 休息模式：直接输出回复
if ($MODE -eq "rest") {
    Write-Host $cmd -ForegroundColor Gray
    exit 0
}

# 工作模式：先检查是否是"非命令"标记（在清理之前检查，避免被清理函数影响）
$cmdTrimmed = $cmd.Trim()
if ($cmdTrimmed -eq "NOT_A_COMMAND" -or $cmdTrimmed -match "^NOT_A_COMMAND") {
    Write-Host "别闹，好好工作。" -ForegroundColor Yellow
    Write-Host "想聊天？用 " -NoNewline -ForegroundColor Gray
    Write-Host "cc -r" -NoNewline -ForegroundColor Green
    Write-Host " 切换到休息模式~" -ForegroundColor Gray
    exit 0
}

# 清理命令并执行
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
