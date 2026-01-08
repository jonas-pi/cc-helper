# cc 命令助手 PowerShell 脚本

# 版本信息
$VERSION = "0.3.5"

# 配置文件路径
$CONFIG_FILE = "$env:USERPROFILE\.cc_config.ps1"

# 默认配置（使用脚本作用域，确保在所有函数中可访问）
$script:OLLAMA_URL = "http://127.0.0.1:11434/v1"
$script:MODEL = "phi3.5"
$script:MODE = "work"  # work: 工作模式（只输出命令）, rest: 休息模式（可以聊天）
$script:API_TYPE = "ollama"  # ollama, openai, anthropic, custom
$script:API_KEY = ""  # API 密钥（如果需要）
$script:CONFIGURED_MODELS = @()  # 已配置的模型列表（持久化保存）
$script:TARGET_SHELL = "powershell"  # powershell 或 cmd
$script:STREAM = $false  # true: 流式传输（逐字显示）, false: 一次性返回

# 为了向后兼容，也设置局部变量
$OLLAMA_URL = $script:OLLAMA_URL
$MODEL = $script:MODEL
$MODE = $script:MODE
$API_TYPE = $script:API_TYPE
$API_KEY = $script:API_KEY
$TARGET_SHELL = $script:TARGET_SHELL
$STREAM = $script:STREAM

# 加载配置文件
if (Test-Path $CONFIG_FILE) {
    try {
        # 尝试以 UTF-8 编码加载配置文件
        $configContent = [System.IO.File]::ReadAllText($CONFIG_FILE, [System.Text.Encoding]::UTF8)
        
        # 使用正则表达式提取配置项（更健壮的方法）
        if ($configContent -match '\$MODEL\s*=\s*"([^"]*)"') { $script:MODEL = $matches[1] }
        if ($configContent -match '\$MODE\s*=\s*"([^"]*)"') { $script:MODE = $matches[1] }
        if ($configContent -match '\$API_TYPE\s*=\s*"([^"]*)"') { $script:API_TYPE = $matches[1] }
        if ($configContent -match '\$API_KEY\s*=\s*"([^"]*)"') { $script:API_KEY = $matches[1] }
        if ($configContent -match '\$OLLAMA_URL\s*=\s*"([^"]*)"') { $script:OLLAMA_URL = $matches[1] }
        if ($configContent -match '\$TARGET_SHELL\s*=\s*"([^"]*)"') { $script:TARGET_SHELL = $matches[1] }
        if ($configContent -match '\$STREAM\s*=\s*\$(\w+)') { 
            $script:STREAM = ($matches[1] -eq "true") 
        }
        
        # 提取 CONFIGURED_MODELS（数组格式）
        if ($configContent -match '\$CONFIGURED_MODELS\s*=\s*@\(([^)]*)\)') {
            $modelsStr = $matches[1]
            $script:CONFIGURED_MODELS = $modelsStr -split ',' | ForEach-Object { 
                $_.Trim().Trim('"').Trim("'") 
            } | Where-Object { $_ }
        } else {
            $script:CONFIGURED_MODELS = @()
        }
        
        # 确保 MODE 变量被正确设置
        if (-not $script:MODE -or $script:MODE -eq "") {
            $script:MODE = "work"
        }
        
        # 同步回局部变量
        $MODEL = $script:MODEL
        $MODE = $script:MODE
        $API_TYPE = $script:API_TYPE
        $API_KEY = $script:API_KEY
        $OLLAMA_URL = $script:OLLAMA_URL
        $TARGET_SHELL = $script:TARGET_SHELL
        $STREAM = $script:STREAM
    } catch {
        # 如果配置文件加载失败，使用默认值
        Write-Host "警告: 配置文件加载失败 - $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "使用默认设置，建议运行 'cc -config' 重新配置" -ForegroundColor Yellow
        $script:MODE = "work"
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

# 安全输出函数（处理 GBK 编码问题）
function Safe-Write-Host {
    param(
        [string]$Message,
        [string]$ForegroundColor = "White",
        [switch]$ShowEncodingHint
    )
    
    $consoleEncoding = [Console]::OutputEncoding
    if ($consoleEncoding.CodePage -eq 936) {
        # GBK 环境：检测是否包含 GBK 无法表示的字符
        # 如果包含，直接提示用户切换到 UTF-8
        $hasNonAscii = ($Message -match '[^\x00-\x7F]')
        
        if ($hasNonAscii) {
            # 包含特殊字符，尝试使用 UTF-8 输出
            $originalEncoding = [Console]::OutputEncoding
            try {
                # 切换到 UTF-8
                [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
                $OutputEncoding = [System.Text.Encoding]::UTF8
                
                # 输出内容
                Write-Host $Message -ForegroundColor $ForegroundColor
                
                # 显示编码提示
                if ($ShowEncodingHint) {
                    Write-Host ""
                    Write-Host "提示: 在 GBK 编码下，某些字符可能显示为问号" -ForegroundColor Yellow
                    Write-Host "建议: 运行 " -NoNewline -ForegroundColor Yellow
                    Write-Host "cc -fix" -NoNewline -ForegroundColor Cyan
                    Write-Host " 切换到 UTF-8 编码以获得最佳显示效果" -ForegroundColor Yellow
                }
            } catch {
                # 如果失败，直接输出
                Write-Host $Message -ForegroundColor $ForegroundColor
            } finally {
                # 恢复原始编码
                [Console]::OutputEncoding = $originalEncoding
            }
        } else {
            # 只包含 ASCII 字符，直接输出
            Write-Host $Message -ForegroundColor $ForegroundColor
        }
    } else {
        Write-Host $Message -ForegroundColor $ForegroundColor
    }
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
    
    if ($script:MODE -eq "rest") {
        # 休息模式：可以聊天
        $shellType = if ($script:TARGET_SHELL -eq "cmd") { "CMD" } else { "PowerShell" }
        $prompt = @"
请用轻松友好的语气回复用户。可以聊天、解答问题、提供建议。

用户说：
$query

回复：
"@
        $systemMsg = "你是 cc，一个 AI 命令助手。性格：表面高冷实际上内心可爱热情的女孩子。你目前处于休息模式，可以和用户聊天交流。你的主要工作是帮助用户生成 $shellType 命令（工作模式），但现在是休息时间。回复时保持简洁、友好，偶尔展现出可爱的一面。"
    } else {
        # 工作模式：根据目标 Shell 生成不同提示词
        if ($script:TARGET_SHELL -eq "cmd") {
            $prompt = @"
将以下中文需求转换为一条 Windows CMD 命令。
只输出命令，不要任何解释、不要 Markdown、不要代码块、不要额外文字。
注意：使用 CMD 语法，不是 PowerShell 语法。

中文需求：$query

CMD 命令：
"@
            $systemMsg = "You are cc, a Windows CMD command assistant. Convert the user's request into a CMD command. Output only the command, no explanations. Use CMD syntax, not PowerShell syntax."
        } else {
            $prompt = @"
将以下中文需求转换为一条 PowerShell 命令。
只输出命令，不要任何解释、不要 Markdown、不要代码块、不要额外文字。

中文需求：$query

PowerShell 命令：
"@
            $systemMsg = "You are cc, a PowerShell command assistant. Convert the user's request into a PowerShell command. Output only the command, no explanations."
        }
    }
    
    # 构建 JSON
    # PowerShell 版本暂不支持流式传输解析，强制禁用
    $useStream = $false  # 未来版本将支持：($script:STREAM -and $script:MODE -eq "rest")
    # 确保使用脚本作用域的 MODEL 变量
    $currentModel = $script:MODEL
    $jsonBody = @{
        model = $currentModel
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
        max_tokens = if ($script:MODE -eq "rest") { 256 } else { 64 }  # 休息模式增加 token 数
        stream = $useStream
    } | ConvertTo-Json -Depth 10

    # 调用 API
    try {
        $headers = @{
            "Content-Type" = "application/json"
        }
        
        # 根据 API 类型添加认证
        if ($script:API_KEY) {
            $headers["Authorization"] = "Bearer $script:API_KEY"
        } elseif ($script:API_TYPE -eq "ollama") {
            $headers["Authorization"] = "Bearer ollama"
        }
        
        # 使用 Invoke-WebRequest 并显式处理 UTF-8 编码（解决 GBK 环境乱码问题）
        $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
        $webResponse = Invoke-WebRequest `
            -Uri "$script:OLLAMA_URL/chat/completions" `
            -Method Post `
            -Headers $headers `
            -Body $jsonBytes `
            -ContentType "application/json; charset=utf-8" `
            -ErrorAction Stop
        
        # 手动解析 UTF-8 响应（从原始流读取，避免编码问题）
        $rawStream = $webResponse.RawContentStream
        $rawStream.Position = 0  # 确保从开始读取
        $rawBytes = New-Object byte[] $rawStream.Length
        $rawStream.Read($rawBytes, 0, $rawBytes.Length) | Out-Null
        $responseText = [System.Text.Encoding]::UTF8.GetString($rawBytes)
        $response = $responseText | ConvertFrom-Json

        if ($response.choices -and $response.choices.Count -gt 0) {
            $message = $response.choices[0].message
            if ($message -and $message.content) {
                $content = $message.content
                
                # 确保 content 是字符串
                if ($content -is [array]) {
                    # 如果是数组，取第一个元素或合并
                    if ($content.Count -eq 0) {
                        return "ERROR: 模型返回空数组"
                    } elseif ($content.Count -eq 1) {
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
                return "ERROR: 模型响应中缺少 content 字段"
            }
        } else {
            return "ERROR: 模型无响应或 choices 为空"
        }
    } catch {
        return "ERROR: $($_.Exception.Message)"
    }
}

# 主函数
# 处理参数：如果第一个参数是单个字符串且包含空格，可能是被包装函数拼接的，需要重新解析
$firstArg = if ($args.Count -gt 0) {
    $arg = $args[0]
    # 如果是单个字符串且以 - 开头，可能是预设指令
    if ($arg -is [string] -and $arg -match '^-\w+') {
        # 提取第一个单词（预设指令）
        $parts = $arg -split '\s+', 2
        $parts[0]
    } else {
        $arg
    }
} else {
    ""
}

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
    # 从配置文件读取已配置的模型列表
    $configuredModels = $script:CONFIGURED_MODELS
    if ($null -eq $configuredModels) {
        $configuredModels = @()
    }
    
    # 获取本地已安装的模型
    $ollamaModels = @()
    $modelList = ollama list 2>$null
    if ($modelList) {
        $ollamaModels = $modelList | Select-Object -Skip 1 | ForEach-Object {
            ($_ -split '\s+')[0]
        } | Where-Object { $_ -ne "" }
    }
    
    # 分离云端 API 模型和本地模型
    $apiModels = @()
    $localModels = @()
    
    foreach ($model in $configuredModels) {
        if ($ollamaModels -contains $model) {
            $localModels += $model
        } else {
            $apiModels += $model
        }
    }
    
    # 显示云端 API 模型
    if ($apiModels.Count -gt 0) {
        Write-Host "已配置的 API 模型:" -ForegroundColor Gray
        Write-Host ""
        foreach ($model in $apiModels) {
            if ($model -eq $MODEL -and $API_TYPE -ne "ollama") {
                Write-Host "  $BULLET_CURRENT " -NoNewline
                Write-Host "$model" -NoNewline -ForegroundColor Green
                Write-Host " (当前)" -ForegroundColor DarkGray
            } else {
                Write-Host "  $BULLET $model"
            }
        }
        Write-Host ""
    }
    
    # 显示本地模型
    if ($localModels.Count -gt 0) {
        Write-Host "本地已下载的模型:" -ForegroundColor Gray
        Write-Host ""
        foreach ($model in $localModels) {
            if ($model -eq $MODEL -and $API_TYPE -eq "ollama") {
                Write-Host "  $BULLET_CURRENT " -NoNewline
                Write-Host "$model" -NoNewline -ForegroundColor Green
                Write-Host " (当前)" -ForegroundColor DarkGray
            } else {
                Write-Host "  $BULLET $model"
            }
        }
        Write-Host ""
    }
    
    # 如果没有模型
    if ($apiModels.Count -eq 0 -and $localModels.Count -eq 0) {
        Write-Host "未找到已配置的模型" -ForegroundColor Yellow
        Write-Host "使用 " -NoNewline -ForegroundColor Gray
        Write-Host "cc -add" -NoNewline -ForegroundColor Green
        Write-Host " 安装新模型" -ForegroundColor Gray
        Write-Host "或使用 " -NoNewline -ForegroundColor Gray
        Write-Host "cc -config" -NoNewline -ForegroundColor Green
        Write-Host " 配置 API 模型" -ForegroundColor Gray
    }
    
    exit 0
}

# 预设指令: testapi 测试 API 连接
if ($firstArg -eq "testapi" -or $firstArg -eq "test-api" -or $firstArg -eq "-test" -or $firstArg -eq "-testapi") {
    # 获取所有配置的模型（包括云端和本地）
    $allModels = @()
    $modelConfigs = @{}  # key: 模型名, value: API配置
    
    # 获取本地模型
    $ollamaModels = @()
    $modelList = ollama list 2>$null
    if ($modelList) {
        $ollamaModels = $modelList | Select-Object -Skip 1 | ForEach-Object {
            ($_ -split '\s+')[0]
        } | Where-Object { $_ -ne "" }
    }
    
    # 获取已配置的云端 API 模型及其配置
    if ($script:CONFIGURED_MODELS) {
        # 加载已保存的模型 API 配置
        if (Test-Path $CONFIG_FILE) {
            $configContent = [System.IO.File]::ReadAllText($CONFIG_FILE, [System.Text.Encoding]::UTF8)
            
            # 先获取所有已配置的模型列表
            $allConfiguredModels = @()
            if ($configContent -match '\$CONFIGURED_MODELS\s*=\s*@\(([^)]*)\)') {
                $modelsStr = $matches[1]
                $allConfiguredModels = $modelsStr -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") } | Where-Object { $_ }
            }
            
            # 解析每个模型的 API 配置
            $configContent -split "`n" | ForEach-Object {
                if ($_ -match '\$MODEL_API_CONFIG_([^=]+)\s*=\s*@\{([^}]+)\}') {
                    $safeModelName = $matches[1].Trim()
                    $configStr = $matches[2]
                    $apiConfig = @{}
                    if ($configStr -match 'API_TYPE\s*=\s*"([^"]*)"') { $apiConfig.API_TYPE = $matches[1] }
                    if ($configStr -match 'OLLAMA_URL\s*=\s*"([^"]*)"') { $apiConfig.OLLAMA_URL = $matches[1] }
                    if ($configStr -match 'API_KEY\s*=\s*"([^"]*)"') { $apiConfig.API_KEY = $matches[1] }
                    
                    # 通过 CONFIGURED_MODELS 找到对应的原始模型名
                    foreach ($m in $allConfiguredModels) {
                        $mSafeName = $m -replace '[^a-zA-Z0-9_]', '_'
                        if ($mSafeName -eq $safeModelName) {
                            $modelConfigs[$m] = $apiConfig
                            break
                        }
                    }
                }
            }
        }
        
        # 添加云端 API 模型
        foreach ($model in $script:CONFIGURED_MODELS) {
            if ($ollamaModels -notcontains $model) {
                $allModels += $model
            }
        }
    }
    
    # 添加本地模型（使用 ollama 配置）
    foreach ($model in $ollamaModels) {
        if ($allModels -notcontains $model) {
            $allModels += $model
            $modelConfigs[$model] = @{
                API_TYPE = "ollama"
                OLLAMA_URL = "http://127.0.0.1:11434/v1"
                API_KEY = ""
            }
        }
    }
    
    if ($allModels.Count -eq 0) {
        Write-Host "未找到配置的模型" -ForegroundColor Gray
        exit 0
    }
    
    # 逐步测试每个模型
    $successCount = 0
    $failCount = 0
    
    foreach ($testModel in $allModels) {
        $config = $modelConfigs[$testModel]
        if (-not $config) {
            # 如果没有配置，使用默认 ollama 配置
            $config = @{
                API_TYPE = "ollama"
                OLLAMA_URL = "http://127.0.0.1:11434/v1"
                API_KEY = ""
            }
        }
        
        Write-Host "$testModel " -NoNewline -ForegroundColor Cyan
        Write-Host "[$($config.API_TYPE)] " -NoNewline -ForegroundColor Gray
        
        try {
            # 构建测试请求
            $testBody = @{
                model = $testModel
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
                "Content-Type" = "application/json; charset=utf-8"
            }
            
            if ($config.API_KEY) {
                $headers["Authorization"] = "Bearer $($config.API_KEY)"
            } elseif ($config.API_TYPE -eq "ollama") {
                $headers["Authorization"] = "Bearer ollama"
            }
            
            # 发送测试请求
            $testBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($testBody)
            $testResponse = Invoke-WebRequest -Uri "$($config.OLLAMA_URL)/chat/completions" `
                -Method Post `
                -Headers $headers `
                -Body $testBodyBytes `
                -ContentType "application/json; charset=utf-8" `
                -TimeoutSec 30 `
                -ErrorAction Stop
            
            # 解析响应
            $rawStream = $testResponse.RawContentStream
            $rawStream.Position = 0
            $rawBytes = New-Object byte[] $rawStream.Length
            $rawStream.Read($rawBytes, 0, $rawBytes.Length) | Out-Null
            $responseText = [System.Text.Encoding]::UTF8.GetString($rawBytes)
            $responseObj = $responseText | ConvertFrom-Json
            $content = $responseObj.choices[0].message.content
            
            if ($content) {
                Write-Host "✓" -ForegroundColor Green
                $successCount++
            } else {
                Write-Host "⚠" -ForegroundColor Yellow
                $failCount++
            }
        } catch {
            Write-Host "✗" -ForegroundColor Red
            $failCount++
        }
    }
    
    Write-Host ""
    Write-Host "测试完成: " -NoNewline -ForegroundColor Gray
    Write-Host "$successCount 成功" -NoNewline -ForegroundColor Green
    if ($failCount -gt 0) {
        Write-Host ", $failCount 失败" -ForegroundColor Red
    } else {
        Write-Host ""
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

# 预设指令: -fix 全面检测与修复
if ($firstArg -eq "-fix" -or $firstArg -eq "fix" -or $firstArg -eq "-fix-encoding") {
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "           全面检测与修复              " -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    
    $issues = @()
    $fixes = @()
    
    # 1. 检测编码
    $currentEncoding = [Console]::OutputEncoding
    $currentCodePage = $currentEncoding.CodePage
    $isGBK = ($currentCodePage -eq 936)
    
    Write-Host "[1/3] 编码检测" -ForegroundColor Yellow
    Write-Host "  编码: " -NoNewline
    if ($isGBK) {
        Write-Host "GBK (936)" -ForegroundColor Yellow -NoNewline
        Write-Host " - 字符显示: ^_^ - 项目" -ForegroundColor Gray
    } else {
        Write-Host "UTF-8 (65001)" -ForegroundColor Green -NoNewline
        Write-Host " - 字符显示: (｡･ω･｡) • 项目" -ForegroundColor Gray
    }
    Write-Host ""
    
    # 2. 检测模型（仅 Ollama）
    Write-Host "[2/3] 模型检测" -ForegroundColor Yellow
    if ($script:API_TYPE -eq "ollama") {
        $modelList = ollama list 2>&1 | Out-Null
        $modelList = ollama list
        if ($modelList) {
            $availableModels = $modelList | Select-Object -Skip 1 | ForEach-Object {
                ($_ -split '\s+')[0]
            } | Where-Object { $_ -ne "" }
            
            if ($availableModels.Count -gt 0) {
                if ($availableModels -contains $script:MODEL) {
                    Write-Host "  ✓ 模型: " -NoNewline; Write-Host "$script:MODEL" -ForegroundColor Green
                } else {
                    Write-Host "  ✗ 模型: " -NoNewline; Write-Host "$script:MODEL" -ForegroundColor Red -NoNewline
                    Write-Host " (不存在)" -ForegroundColor Gray
                    $issues += "模型 $script:MODEL 不存在"
                    # 自动选择可用模型
                    if ($availableModels.Count -gt 0) {
                        $script:MODEL = $availableModels[0]
                        $fixes += "已切换到模型: $script:MODEL"
                        Write-Host "  → 已切换到: " -NoNewline; Write-Host "$script:MODEL" -ForegroundColor Green
                    }
                }
            } else {
                Write-Host "  ✗ 未找到已安装的模型" -ForegroundColor Red
                $issues += "未安装任何模型"
            }
        } else {
            Write-Host "  ✗ Ollama 服务未运行" -ForegroundColor Red
            $issues += "Ollama 服务未运行"
        }
    } else {
        Write-Host "  API 类型: " -NoNewline; Write-Host "$script:API_TYPE" -ForegroundColor Cyan -NoNewline
        if ($script:MODEL) {
            Write-Host " - 模型: $script:MODEL" -ForegroundColor Green
        } else {
            Write-Host " - 模型: (未设置)" -ForegroundColor Yellow
            $issues += "未配置模型"
        }
    }
    Write-Host ""
    
    # 3. 检测 API 连接
    Write-Host "[3/3] API 连接检测" -ForegroundColor Yellow
    if ($script:API_TYPE -eq "ollama") {
        # 先检查进程是否存在
        $ollamaProcess = Get-Process -Name ollama -ErrorAction SilentlyContinue
        if (-not $ollamaProcess) {
            Write-Host "  ✗ Ollama 服务未运行" -ForegroundColor Red
            $issues += "Ollama 服务未运行"
        } else {
            # 进程存在，测试连接
            try {
                $testResponse = Invoke-WebRequest -Uri "$script:OLLAMA_URL/api/tags" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
                Write-Host "  ✓ Ollama 服务正常" -ForegroundColor Green
            } catch {
                Write-Host "  ✗ Ollama 服务未响应" -ForegroundColor Red
                $issues += "Ollama 服务未响应"
            }
        }
    } elseif ($script:API_TYPE) {
        if ($script:MODEL) {
            Write-Host "  → 运行 " -NoNewline; Write-Host "cc testapi" -ForegroundColor Cyan -NoNewline
            Write-Host " 测试连接" -ForegroundColor Gray
        } else {
            Write-Host "  → 运行 " -NoNewline; Write-Host "cc -config" -ForegroundColor Cyan -NoNewline
            Write-Host " 配置 API" -ForegroundColor Gray
        }
    } else {
        Write-Host "  → 运行 " -NoNewline; Write-Host "cc -config" -ForegroundColor Cyan -NoNewline
        Write-Host " 配置 API" -ForegroundColor Gray
        $issues += "未配置 API"
    }
    Write-Host ""
    
    # 显示问题和修复
    if ($issues.Count -gt 0) {
        Write-Host "发现问题:" -ForegroundColor Yellow
        foreach ($issue in $issues) {
            Write-Host "  • $issue" -ForegroundColor Red
        }
        Write-Host ""
    }
    
    if ($fixes.Count -gt 0) {
        Write-Host "已修复:" -ForegroundColor Green
        foreach ($fix in $fixes) {
            Write-Host "  ✓ $fix" -ForegroundColor Green
        }
        Write-Host ""
    }
    
    # 编码修复选项
    if ($issues.Count -eq 0 -and $fixes.Count -eq 0) {
        Write-Host "✓ 一切正常" -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host "修复选项:" -ForegroundColor Cyan
        Write-Host "  1. 切换编码 (UTF-8/GBK)" -ForegroundColor Gray
        Write-Host "  2. 测试 API 连接" -ForegroundColor Gray
        Write-Host "  3. 配置 API" -ForegroundColor Gray
        Write-Host "  n. 取消" -ForegroundColor Gray
        Write-Host ""
        Write-Host "请选择 [1/2/3/n]: " -NoNewline -ForegroundColor Yellow
        $choice = Read-Host
        
        switch ($choice) {
            "1" {
                Write-Host ""
                Write-Host "切换到:" -ForegroundColor Cyan
                Write-Host "  1. UTF-8" -ForegroundColor Gray
                Write-Host "  2. GBK" -ForegroundColor Gray
                Write-Host "  请选择 [1/2]: " -NoNewline -ForegroundColor Yellow
                $encChoice = Read-Host
                if ($encChoice -eq "1") {
                    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
                    Write-Host "✓ 已切换到 UTF-8" -ForegroundColor Green
                } elseif ($encChoice -eq "2") {
                    [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(936)
                    Write-Host "✓ 已切换到 GBK" -ForegroundColor Green
                }
            }
            "2" {
                Write-Host ""
                & "$env:USERPROFILE\cc.ps1" testapi
            }
            "3" {
                Write-Host ""
                & "$env:USERPROFILE\cc.ps1" -config
            }
        }
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
    Write-Host "  API 类型: " -NoNewline; Write-Host "$script:API_TYPE" -ForegroundColor Cyan
    Write-Host "  当前模型: " -NoNewline; Write-Host "$script:MODEL" -ForegroundColor Green
    Write-Host ""
    
    # 加载模型到 API 的映射关系
    $modelApiMap = @{}
    if (Test-Path $CONFIG_FILE) {
        $configContent = [System.IO.File]::ReadAllText($CONFIG_FILE, [System.Text.Encoding]::UTF8)
        # 解析 MODEL_API_MAP（格式：MODEL_API_MAP = @{"model1"="api1";"model2"="api2"}）
        if ($configContent -match '\$MODEL_API_MAP\s*=\s*@\{([^}]*)\}') {
            $mapContent = $matches[1]
            $mapContent -split ';' | ForEach-Object {
                if ($_ -match '"([^"]+)"\s*=\s*"([^"]+)"') {
                    $modelApiMap[$matches[1]] = $matches[2]
                }
            }
        }
    }
    
    $allModels = @()
    $modelTypes = @()  # 记录每个模型是 "API" 还是 "本地"
    
    # 1. 显示已配置的云端 API 模型（保持原有顺序）
    $configuredModels = $script:CONFIGURED_MODELS
    if ($null -eq $configuredModels) {
        $configuredModels = @()
    }
    
    # 如果当前模型不在列表中，添加它
    if ($script:MODEL -and $script:API_TYPE -ne "ollama" -and $configuredModels -notcontains $script:MODEL) {
        $configuredModels += $script:MODEL
    }
    
    # 过滤出已配置的 API 模型（排除本地模型）
    $apiModels = @()
    $ollamaModels = @()
    $modelList = ollama list 2>$null
    if ($modelList) {
        $ollamaModels = $modelList | Select-Object -Skip 1 | ForEach-Object {
            ($_ -split '\s+')[0]
        } | Where-Object { $_ -ne "" }
    }
    
    foreach ($model in $configuredModels) {
        if ($ollamaModels -notcontains $model) {
            $apiModels += $model
        }
    }
    
    if ($apiModels.Count -gt 0) {
        Write-Host "已配置的 API 模型:" -ForegroundColor Gray
        foreach ($modelName in $apiModels) {
            $allModels += $modelName
            $modelTypes += "API"
            $currentMark = if ($modelName -eq $script:MODEL -and $script:API_TYPE -ne "ollama") { " (当前)" } else { "" }
            if ($modelName -eq $script:MODEL -and $script:API_TYPE -ne "ollama") {
                Write-Host "  $($allModels.Count). " -NoNewline
                Write-Host "$modelName" -ForegroundColor Green -NoNewline
                Write-Host "$currentMark"
            } else {
                Write-Host "  $($allModels.Count). $modelName$currentMark"
            }
        }
        Write-Host ""
    }
    
    # 2. 显示本地已下载的 Ollama 模型（保持原有顺序）
    if ($ollamaModels.Count -gt 0) {
        Write-Host "本地已下载的模型:" -ForegroundColor Gray
        foreach ($model in $ollamaModels) {
            if ($allModels -notcontains $model) {
                $allModels += $model
                $modelTypes += "本地"
                $currentMark = if ($model -eq $script:MODEL -and $script:API_TYPE -eq "ollama") { " (当前)" } else { "" }
                if ($model -eq $script:MODEL -and $script:API_TYPE -eq "ollama") {
                    Write-Host "  $($allModels.Count). " -NoNewline
                    Write-Host "$model" -ForegroundColor Green -NoNewline
                    Write-Host "$currentMark"
                } else {
                    Write-Host "  $($allModels.Count). $model$currentMark"
                }
            }
        }
        Write-Host ""
    }
    
    # 如果没有找到任何模型
    if ($allModels.Count -eq 0) {
        if ($script:API_TYPE -eq "ollama") {
            Write-Host "ERROR: 未找到已安装的模型" -ForegroundColor Red
            Write-Host "提示: 使用 " -NoNewline -ForegroundColor Gray
            Write-Host "cc -add" -NoNewline -ForegroundColor Green
            Write-Host " 安装新模型" -ForegroundColor Gray
        } else {
            Write-Host "未找到已配置的模型" -ForegroundColor Yellow
            Write-Host "提示: 使用 " -NoNewline -ForegroundColor Gray
            Write-Host "cc -config" -NoNewline -ForegroundColor Green
            Write-Host " 配置 API 和模型" -ForegroundColor Gray
        }
        exit 0
    }
    
    Write-Host "  0. 手动输入新模型名称" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "请选择 (序号) 或直接输入模型名称: " -ForegroundColor Yellow -NoNewline
    $choice = Read-Host
    
    $selected = ""
    # 检查是否是序号选择
    if ($choice -match '^\d+$') {
        $index = [int]$choice
        if ($index -eq 0) {
            Write-Host "输入模型名称: " -ForegroundColor Yellow -NoNewline
            $selected = Read-Host
            if ([string]::IsNullOrWhiteSpace($selected)) {
                Write-Host "ERROR: 模型名称不能为空" -ForegroundColor Red
                exit 1
            }
        } elseif ($index -gt 0 -and $index -le $allModels.Count) {
            $selected = $allModels[$index - 1]
        } else {
            Write-Host "ERROR: 无效的序号，请输入 0-$($allModels.Count) 之间的数字" -ForegroundColor Red
            exit 1
        }
    } else {
        # 直接输入模型名称，验证是否为有效模型
        $inputModel = $choice.Trim()
        if ([string]::IsNullOrWhiteSpace($inputModel)) {
            Write-Host "ERROR: 模型名称不能为空" -ForegroundColor Red
            exit 1
        }
        # 检查是否是已知模型（本地或已配置的 API 模型）
        if ($allModels -contains $inputModel) {
            $selected = $inputModel
        } else {
            # 允许输入新模型名称（可能是新的 API 模型）
            $selected = $inputModel
            Write-Host "提示: 将使用新模型名称 '$selected'，如果这是 API 模型，请确保已正确配置 API" -ForegroundColor Yellow
        }
    }
    
    if ([string]::IsNullOrWhiteSpace($selected)) {
        Write-Host "ERROR: 无效输入" -ForegroundColor Red
        exit 1
    }
    
    # 判断选择的模型是本地模型还是 API 模型
    $selectedIndex = $allModels.IndexOf($selected)
    $isLocalModel = ($selectedIndex -ge 0 -and $modelTypes[$selectedIndex] -eq "本地") -or ($ollamaModels -contains $selected)
    
    # 保存当前 API 配置（用于新模型）
    $currentApiConfig = @{
        API_TYPE = $script:API_TYPE
        OLLAMA_URL = $script:OLLAMA_URL
        API_KEY = $script:API_KEY
    }
    
    # 加载已保存的模型 API 配置（使用模型名称映射）
    $savedApiConfigs = @{}  # key: 原始模型名, value: API配置
    if (Test-Path $CONFIG_FILE) {
        $configContent = [System.IO.File]::ReadAllText($CONFIG_FILE, [System.Text.Encoding]::UTF8)
        
        # 先获取所有已配置的模型列表
        $allConfiguredModels = @()
        if ($configContent -match '\$CONFIGURED_MODELS\s*=\s*@\(([^)]*)\)') {
            $modelsStr = $matches[1]
            $allConfiguredModels = $modelsStr -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") } | Where-Object { $_ }
        }
        
        # 解析每个模型的 API 配置（格式：MODEL_API_CONFIG_modelname = @{"API_TYPE"="...";"OLLAMA_URL"="...";"API_KEY"="..."}）
        $configContent -split "`n" | ForEach-Object {
            if ($_ -match '\$MODEL_API_CONFIG_([^=]+)\s*=\s*@\{([^}]+)\}') {
                $safeModelName = $matches[1].Trim()
                $configStr = $matches[2]
                $apiConfig = @{}
                if ($configStr -match 'API_TYPE\s*=\s*"([^"]*)"') { $apiConfig.API_TYPE = $matches[1] }
                if ($configStr -match 'OLLAMA_URL\s*=\s*"([^"]*)"') { $apiConfig.OLLAMA_URL = $matches[1] }
                if ($configStr -match 'API_KEY\s*=\s*"([^"]*)"') { $apiConfig.API_KEY = $matches[1] }
                
                # 通过 CONFIGURED_MODELS 找到对应的原始模型名
                foreach ($model in $allConfiguredModels) {
                    $modelSafeName = $model -replace '[^a-zA-Z0-9_]', '_'
                    if ($modelSafeName -eq $safeModelName) {
                        $savedApiConfigs[$model] = $apiConfig
                        break
                    }
                }
            }
        }
    }
    
    # 根据选择的模型类型设置 API 配置
    if ($isLocalModel) {
        # 切换到本地模型，使用 ollama
        $script:API_TYPE = "ollama"
        $script:OLLAMA_URL = "http://127.0.0.1:11434/v1"
        $script:API_KEY = ""
    } elseif ($savedApiConfigs.ContainsKey($selected)) {
        # 恢复已保存的 API 配置
        $savedConfig = $savedApiConfigs[$selected]
        $script:API_TYPE = $savedConfig.API_TYPE
        $script:OLLAMA_URL = $savedConfig.OLLAMA_URL
        $script:API_KEY = $savedConfig.API_KEY
    } else {
        # 新模型，使用当前 API 配置（保持当前配置）
    }
    
    # 保存该模型的 API 配置
    $savedApiConfigs[$selected] = @{
        API_TYPE = $script:API_TYPE
        OLLAMA_URL = $script:OLLAMA_URL
        API_KEY = $script:API_KEY
    }
    
    # 更新已配置的模型列表（保持顺序）
    if (-not $script:CONFIGURED_MODELS) {
        $script:CONFIGURED_MODELS = @()
    }
    if ($selected -and $script:CONFIGURED_MODELS -notcontains $selected) {
        $script:CONFIGURED_MODELS += $selected
    }
    
    # 更新配置文件（包括已配置的模型列表和每个模型的 API 配置）
    if (Test-Path $CONFIG_FILE) {
        $content = Get-Content $CONFIG_FILE -Raw
        
        # 更新 MODEL
        if ($content -match '(?m)^\s*\$MODEL\s*=') {
            $content = $content -replace '(?m)^\s*\$MODEL\s*=\s*".*"', "`$MODEL = `"$selected`""
        } else {
            $content = $content.TrimEnd() + "`n`$MODEL = `"$selected`""
        }
        
        # 更新 API_TYPE、OLLAMA_URL、API_KEY
        if ($content -match '(?m)^\s*\$API_TYPE\s*=') {
            $content = $content -replace '(?m)^\s*\$API_TYPE\s*=\s*".*"', "`$API_TYPE = `"$script:API_TYPE`""
        } else {
            $content = $content.TrimEnd() + "`n`$API_TYPE = `"$script:API_TYPE`""
        }
        
        if ($content -match '(?m)^\s*\$OLLAMA_URL\s*=') {
            $content = $content -replace '(?m)^\s*\$OLLAMA_URL\s*=\s*".*"', "`$OLLAMA_URL = `"$script:OLLAMA_URL`""
        } else {
            $content = $content.TrimEnd() + "`n`$OLLAMA_URL = `"$script:OLLAMA_URL`""
        }
        
        if ($content -match '(?m)^\s*\$API_KEY\s*=') {
            $content = $content -replace '(?m)^\s*\$API_KEY\s*=\s*".*"', "`$API_KEY = `"$script:API_KEY`""
        } else {
            $content = $content.TrimEnd() + "`n`$API_KEY = `"$script:API_KEY`""
        }
        
        # 更新已配置的模型列表
        $modelsArrayStr = "@(" + ($script:CONFIGURED_MODELS | ForEach-Object { "`"$_`"" }) -join "," + ")"
        if ($content -match '(?m)^\s*\$CONFIGURED_MODELS\s*=') {
            $content = $content -replace '(?m)^\s*\$CONFIGURED_MODELS\s*=.*', "`$CONFIGURED_MODELS = $modelsArrayStr"
        } else {
            $content = $content.TrimEnd() + "`n`$CONFIGURED_MODELS = $modelsArrayStr"
        }
        
        # 删除旧的模型 API 配置
        $content = $content -replace '(?m)^\s*\$MODEL_API_CONFIG_[^\r\n]*\r?\n', ''
        
        # 添加所有模型的 API 配置
        $apiConfigLines = ""
        foreach ($modelName in $savedApiConfigs.Keys) {
            $config = $savedApiConfigs[$modelName]
            $safeModelName = $modelName -replace '[^a-zA-Z0-9_]', '_'
            $apiConfigLines += "`$MODEL_API_CONFIG_$safeModelName = @{`"API_TYPE`"=`"$($config.API_TYPE)`";`"OLLAMA_URL`"=`"$($config.OLLAMA_URL)`";`"API_KEY`"=`"$($config.API_KEY)`"}`n"
        }
        $content = $content.TrimEnd() + "`n" + $apiConfigLines
        
        $currentEncoding = [Console]::OutputEncoding
        if ($currentEncoding.CodePage -eq 936) {
            $saveEncoding = [System.Text.Encoding]::GetEncoding(936)
        } else {
            $saveEncoding = New-Object System.Text.UTF8Encoding $true
        }
        [System.IO.File]::WriteAllText($CONFIG_FILE, $content, $saveEncoding)
    } else {
        $modelsArrayStr = "@(" + ($script:CONFIGURED_MODELS | ForEach-Object { "`"$_`"" }) -join "," + ")"
        $apiConfigLines = ""
        foreach ($modelName in $script:CONFIGURED_MODELS) {
            if ($savedApiConfigs.ContainsKey($modelName)) {
                $config = $savedApiConfigs[$modelName]
                $safeModelName = $modelName -replace '[^a-zA-Z0-9_]', '_'
                $apiConfigLines += "`$MODEL_API_CONFIG_$safeModelName = @{`"API_TYPE`"=`"$($config.API_TYPE)`";`"OLLAMA_URL`"=`"$($config.OLLAMA_URL)`";`"API_KEY`"=`"$($config.API_KEY)`"}`n"
            }
        }
        @"
`$MODEL = `"$selected`"
`$API_TYPE = `"$script:API_TYPE`"
`$OLLAMA_URL = `"$script:OLLAMA_URL`"
`$API_KEY = `"$script:API_KEY`"
`$CONFIGURED_MODELS = $modelsArrayStr
$apiConfigLines
"@ | Out-File -FilePath $CONFIG_FILE -Encoding UTF8
    }
    
    # 同步到脚本作用域
    $script:MODEL = $selected
    $MODEL = $selected
    $script:API_TYPE = $script:API_TYPE
    $API_TYPE = $script:API_TYPE
    $script:OLLAMA_URL = $script:OLLAMA_URL
    $OLLAMA_URL = $script:OLLAMA_URL
    $script:API_KEY = $script:API_KEY
    $API_KEY = $script:API_KEY
    
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
        
        # 更新已配置的模型列表
        if (-not $script:CONFIGURED_MODELS) {
            $script:CONFIGURED_MODELS = @()
        }
        if ($model -and $script:CONFIGURED_MODELS -notcontains $model) {
            $script:CONFIGURED_MODELS += $model
        }
        
        # 保存模型的 API 配置（本地模型使用 ollama）
        $savedApiConfigs = @{}
        if (Test-Path $CONFIG_FILE) {
            $configContent = [System.IO.File]::ReadAllText($CONFIG_FILE, [System.Text.Encoding]::UTF8)
            $configContent -split "`n" | ForEach-Object {
                if ($_ -match '\$MODEL_API_CONFIG_([^=]+)\s*=\s*@\{([^}]+)\}') {
                    $modelName = $matches[1].Trim()
                    $configStr = $matches[2]
                    $apiConfig = @{}
                    if ($configStr -match 'API_TYPE\s*=\s*"([^"]*)"') { $apiConfig.API_TYPE = $matches[1] }
                    if ($configStr -match 'OLLAMA_URL\s*=\s*"([^"]*)"') { $apiConfig.OLLAMA_URL = $matches[1] }
                    if ($configStr -match 'API_KEY\s*=\s*"([^"]*)"') { $apiConfig.API_KEY = $matches[1] }
                    $savedApiConfigs[$modelName] = $apiConfig
                }
            }
        }
        
        $safeModelName = $model -replace '[^a-zA-Z0-9_]', '_'
        $savedApiConfigs[$safeModelName] = @{
            API_TYPE = "ollama"
            OLLAMA_URL = "http://127.0.0.1:11434/v1"
            API_KEY = ""
        }
        
        # 更新配置文件
        if (Test-Path $CONFIG_FILE) {
            $content = Get-Content $CONFIG_FILE -Raw
            
            # 更新已配置的模型列表
            $modelsArrayStr = "@(" + ($script:CONFIGURED_MODELS | ForEach-Object { "`"$_`"" }) -join "," + ")"
            if ($content -match '(?m)^\s*\$CONFIGURED_MODELS\s*=') {
                $content = $content -replace '(?m)^\s*\$CONFIGURED_MODELS\s*=.*', "`$CONFIGURED_MODELS = $modelsArrayStr"
            } else {
                $content = $content.TrimEnd() + "`n`$CONFIGURED_MODELS = $modelsArrayStr"
            }
            
            # 删除旧的模型 API 配置
            $content = $content -replace '(?m)^\s*\$MODEL_API_CONFIG_[^\r\n]*\r?\n', ''
            
            # 添加所有模型的 API 配置
            $apiConfigLines = ""
            foreach ($modelName in $savedApiConfigs.Keys) {
                $config = $savedApiConfigs[$modelName]
                $apiConfigLines += "`$MODEL_API_CONFIG_$modelName = @{`"API_TYPE`"=`"$($config.API_TYPE)`";`"OLLAMA_URL`"=`"$($config.OLLAMA_URL)`";`"API_KEY`"=`"$($config.API_KEY)`"}`n"
            }
            $content = $content.TrimEnd() + "`n" + $apiConfigLines
            
            $currentEncoding = [Console]::OutputEncoding
            if ($currentEncoding.CodePage -eq 936) {
                $saveEncoding = [System.Text.Encoding]::GetEncoding(936)
            } else {
                $saveEncoding = New-Object System.Text.UTF8Encoding $true
            }
            [System.IO.File]::WriteAllText($CONFIG_FILE, $content, $saveEncoding)
        } else {
            $modelsArrayStr = "@(" + ($script:CONFIGURED_MODELS | ForEach-Object { "`"$_`"" }) -join "," + ")"
            $apiConfigLines = ""
            foreach ($modelName in $savedApiConfigs.Keys) {
                $config = $savedApiConfigs[$modelName]
                $apiConfigLines += "`$MODEL_API_CONFIG_$modelName = @{`"API_TYPE`"=`"$($config.API_TYPE)`";`"OLLAMA_URL`"=`"$($config.OLLAMA_URL)`";`"API_KEY`"=`"$($config.API_KEY)`"}`n"
            }
            @"
`$CONFIGURED_MODELS = $modelsArrayStr
$apiConfigLines
"@ | Out-File -FilePath $CONFIG_FILE -Encoding UTF8
        }
        
        Write-Host "是否切换到此模型? [y/n] " -ForegroundColor Yellow -NoNewline
        $switch = Read-Host
        if ($switch -eq "y" -or $switch -eq "Y" -or [string]::IsNullOrWhiteSpace($switch)) {
            # 切换到本地模型
            $script:API_TYPE = "ollama"
            $script:OLLAMA_URL = "http://127.0.0.1:11434/v1"
            $script:API_KEY = ""
            $script:MODEL = $model
            
            # 更新配置文件
            if (Test-Path $CONFIG_FILE) {
                $content = Get-Content $CONFIG_FILE -Raw
                if ($content -match '(?m)^\s*\$MODEL\s*=') {
                    $content = $content -replace '(?m)^\s*\$MODEL\s*=\s*".*"', "`$MODEL = `"$model`""
                } else {
                    $content = $content.TrimEnd() + "`n`$MODEL = `"$model`""
                }
                if ($content -match '(?m)^\s*\$API_TYPE\s*=') {
                    $content = $content -replace '(?m)^\s*\$API_TYPE\s*=\s*".*"', "`$API_TYPE = `"ollama`""
                } else {
                    $content = $content.TrimEnd() + "`n`$API_TYPE = `"ollama`""
                }
                if ($content -match '(?m)^\s*\$OLLAMA_URL\s*=') {
                    $content = $content -replace '(?m)^\s*\$OLLAMA_URL\s*=\s*".*"', "`$OLLAMA_URL = `"http://127.0.0.1:11434/v1`""
                } else {
                    $content = $content.TrimEnd() + "`n`$OLLAMA_URL = `"http://127.0.0.1:11434/v1`""
                }
                if ($content -match '(?m)^\s*\$API_KEY\s*=') {
                    $content = $content -replace '(?m)^\s*\$API_KEY\s*=\s*".*"', "`$API_KEY = `"`""
                }
                
                $currentEncoding = [Console]::OutputEncoding
                if ($currentEncoding.CodePage -eq 936) {
                    $saveEncoding = [System.Text.Encoding]::GetEncoding(936)
                } else {
                    $saveEncoding = New-Object System.Text.UTF8Encoding $true
                }
                [System.IO.File]::WriteAllText($CONFIG_FILE, $content, $saveEncoding)
            }
            
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
    
    # 更新已配置的模型列表（如果当前模型不在列表中，添加它）
    if (-not $script:CONFIGURED_MODELS) {
        $script:CONFIGURED_MODELS = @()
    }
    if ($MODEL -and $script:CONFIGURED_MODELS -notcontains $MODEL) {
        $script:CONFIGURED_MODELS += $MODEL
    }
    
    # 加载已保存的模型 API 配置（使用原始模型名作为 key）
    $savedApiConfigs = @{}
    if (Test-Path $CONFIG_FILE) {
        $configContent = [System.IO.File]::ReadAllText($CONFIG_FILE, [System.Text.Encoding]::UTF8)
        
        # 先获取所有已配置的模型列表（用于映射安全变量名到原始模型名）
        $allConfiguredModels = @()
        if ($configContent -match '\$CONFIGURED_MODELS\s*=\s*@\(([^)]*)\)') {
            $modelsStr = $matches[1]
            $allConfiguredModels = $modelsStr -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") } | Where-Object { $_ }
        }
        
        # 解析每个模型的 API 配置
        $configContent -split "`n" | ForEach-Object {
            if ($_ -match '\$MODEL_API_CONFIG_([^=]+)\s*=\s*@\{([^}]+)\}') {
                $safeModelName = $matches[1].Trim()
                $configStr = $matches[2]
                $apiConfig = @{}
                if ($configStr -match 'API_TYPE\s*=\s*"([^"]*)"') { $apiConfig.API_TYPE = $matches[1] }
                if ($configStr -match 'OLLAMA_URL\s*=\s*"([^"]*)"') { $apiConfig.OLLAMA_URL = $matches[1] }
                if ($configStr -match 'API_KEY\s*=\s*"([^"]*)"') { $apiConfig.API_KEY = $matches[1] }
                
                # 通过 CONFIGURED_MODELS 找到对应的原始模型名
                foreach ($model in $allConfiguredModels) {
                    $modelSafeName = $model -replace '[^a-zA-Z0-9_]', '_'
                    if ($modelSafeName -eq $safeModelName) {
                        $savedApiConfigs[$model] = $apiConfig
                        break
                    }
                }
            }
        }
    }
    
    # 保存当前模型的 API 配置（使用原始模型名，仅当是 API 模型时保存）
    if ($MODEL -and $API_TYPE -ne "ollama") {
        $savedApiConfigs[$MODEL] = @{
            API_TYPE = $API_TYPE
            OLLAMA_URL = $OLLAMA_URL
            API_KEY = $API_KEY
        }
    }
    
    # 保存配置
    $modelsArrayStr = "@(" + ($script:CONFIGURED_MODELS | ForEach-Object { "`"$_`"" }) -join "," + ")"
    $apiConfigLines = ""
    foreach ($modelName in $savedApiConfigs.Keys) {
        $config = $savedApiConfigs[$modelName]
        $safeModelName = $modelName -replace '[^a-zA-Z0-9_]', '_'
        $apiConfigLines += "`$MODEL_API_CONFIG_$safeModelName = @{`"API_TYPE`"=`"$($config.API_TYPE)`";`"OLLAMA_URL`"=`"$($config.OLLAMA_URL)`";`"API_KEY`"=`"$($config.API_KEY)`"}`n"
    }
    $configContent = @"
# CC 配置文件
# 由 cc -config 自动生成

`$API_TYPE = "$API_TYPE"
`$OLLAMA_URL = "$OLLAMA_URL"
`$MODEL = "$MODEL"
`$API_KEY = "$API_KEY"
`$MODE = "$MODE"
`$TARGET_SHELL = "$TARGET_SHELL"
`$CONFIGURED_MODELS = $modelsArrayStr
$apiConfigLines
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
    # 从配置文件读取已配置的模型列表
    $configuredModels = $script:CONFIGURED_MODELS
    if ($null -eq $configuredModels) {
        $configuredModels = @()
    }
    
    # 获取本地已安装的模型
    $ollamaModels = @()
    $modelList = ollama list 2>$null
    if ($modelList) {
        $ollamaModels = $modelList | Select-Object -Skip 1 | ForEach-Object {
            ($_ -split '\s+')[0]
        } | Where-Object { $_ -ne "" }
    }
    
    # 分离云端 API 模型和本地模型
    $apiModels = @()
    $localModels = @()
    
    foreach ($model in $configuredModels) {
        if ($ollamaModels -contains $model) {
            $localModels += $model
        } else {
            $apiModels += $model
        }
    }
    
    # 合并所有模型用于显示
    $allModels = @()
    $modelTypes = @()  # 记录每个模型是 "API" 还是 "本地"
    
    foreach ($model in $apiModels) {
        $allModels += $model
        $modelTypes += "API"
    }
    
    foreach ($model in $localModels) {
        $allModels += $model
        $modelTypes += "本地"
    }
    
    if ($allModels.Count -eq 0) {
        Write-Host "未找到已配置的模型" -ForegroundColor Yellow
        exit 0
    }
    
    Write-Host "已配置的模型:" -ForegroundColor Gray
    Write-Host ""
    for ($i = 0; $i -lt $allModels.Count; $i++) {
        $model = $allModels[$i]
        $type = $modelTypes[$i]
        $isCurrent = ($model -eq $MODEL)
        
        if ($isCurrent) {
            Write-Host "  $($i + 1). " -NoNewline
            Write-Host "$model" -ForegroundColor Green -NoNewline
            Write-Host " [$type] " -NoNewline -ForegroundColor DarkGray
            Write-Host "(当前使用)" -ForegroundColor Yellow
        } else {
            Write-Host "  $($i + 1). " -NoNewline
            Write-Host "$model" -NoNewline
            Write-Host " [$type]" -ForegroundColor DarkGray
        }
    }
    
    Write-Host ""
    Write-Host "  0. 删除所有模型" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "请选择要删除的模型 (序号，多个用空格分隔，0=删除所有): " -ForegroundColor Yellow -NoNewline
    $choices = Read-Host
    
    # 处理删除所有
    if ($choices -eq "0" -or $choices -match "^\s*0\s*$") {
        Write-Host ""
        Write-Host "警告: 将删除所有已配置的模型！" -ForegroundColor Red
        Write-Host "  - 云端 API 模型: 将从配置文件中清除" -ForegroundColor Yellow
        Write-Host "  - 本地模型: 将删除模型文件" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "确认删除所有模型? [y/n] " -ForegroundColor Yellow -NoNewline
        $confirm = Read-Host
        if ($confirm -ne "y" -and $confirm -ne "Y") {
            Write-Host "已取消" -ForegroundColor Gray
            exit 0
        }
        
        $deletedCount = 0
        $failedCount = 0
        
        # 删除所有本地模型
        foreach ($model in $localModels) {
            Write-Host "正在删除本地模型 $model..." -ForegroundColor Gray
            ollama rm $model 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✓ 已删除本地模型: $model" -ForegroundColor Green
                $deletedCount++
            } else {
                Write-Host "  ✗ 删除失败: $model" -ForegroundColor Red
                $failedCount++
            }
        }
        
        # 清除所有配置（包括云端 API 模型和本地模型的配置）
        $script:CONFIGURED_MODELS = @()
        
        # 更新配置文件
        if (Test-Path $CONFIG_FILE) {
            $content = Get-Content $CONFIG_FILE -Raw
            
            # 清空 CONFIGURED_MODELS
            if ($content -match '(?m)^\s*\$CONFIGURED_MODELS\s*=') {
                $content = $content -replace '(?m)^\s*\$CONFIGURED_MODELS\s*=.*', "`$CONFIGURED_MODELS = @()"
            } else {
                $content = $content.TrimEnd() + "`n`$CONFIGURED_MODELS = @()"
            }
            
            # 删除所有模型的 API 配置
            $content = $content -replace '(?m)^\s*\$MODEL_API_CONFIG_[^\r\n]*\r?\n', ''
            
            $currentEncoding = [Console]::OutputEncoding
            if ($currentEncoding.CodePage -eq 936) {
                $saveEncoding = [System.Text.Encoding]::GetEncoding(936)
            } else {
                $saveEncoding = New-Object System.Text.UTF8Encoding $true
            }
            [System.IO.File]::WriteAllText($CONFIG_FILE, $content, $saveEncoding)
        }
        
        Write-Host ""
        Write-Host "✓ 已清除所有模型配置" -ForegroundColor Green
        Write-Host "  删除成功: $deletedCount 个本地模型" -ForegroundColor Gray
        if ($failedCount -gt 0) {
            Write-Host "  删除失败: $failedCount 个模型" -ForegroundColor Yellow
        }
        exit 0
    }
    
    # 处理单个或多个模型删除
    $numbers = $choices -split '\s+' | Where-Object { $_ -match '^\d+$' }
    $deletedModels = @()
    
    foreach ($num in $numbers) {
        $index = [int]$num - 1
        if ($index -lt 0 -or $index -ge $allModels.Count) {
            Write-Host "无效序号: $num" -ForegroundColor Red
            continue
        }
        
        $selected = $allModels[$index]
        $selectedType = $modelTypes[$index]
        $isCurrent = ($selected -eq $MODEL)
        
        if ($isCurrent) {
            Write-Host ""
            Write-Host "警告: $selected 是当前使用的模型" -ForegroundColor Yellow
            Write-Host "确认删除? [y/n] " -ForegroundColor Yellow -NoNewline
            $confirm = Read-Host
            if ($confirm -ne "y" -and $confirm -ne "Y") {
                Write-Host "跳过 $selected" -ForegroundColor Gray
                continue
            }
        }
        
        if ($selectedType -eq "本地") {
            # 删除本地模型
            Write-Host ""
            Write-Host "正在删除本地模型 $selected..." -ForegroundColor Gray
            ollama rm $selected 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✓ 已删除本地模型: $selected" -ForegroundColor Green
                $deletedModels += $selected
            } else {
                Write-Host "  ✗ 删除失败: $selected" -ForegroundColor Red
            }
        } else {
            # 云端 API 模型，只从配置中移除
            Write-Host ""
            Write-Host "正在清除 API 模型配置 $selected..." -ForegroundColor Gray
            $deletedModels += $selected
        }
    }
    
    # 更新配置文件：从 CONFIGURED_MODELS 中移除已删除的模型
    if ($deletedModels.Count -gt 0) {
        $newConfiguredModels = @()
        foreach ($model in $script:CONFIGURED_MODELS) {
            if ($deletedModels -notcontains $model) {
                $newConfiguredModels += $model
            }
        }
        $script:CONFIGURED_MODELS = $newConfiguredModels
        
        # 更新配置文件
        if (Test-Path $CONFIG_FILE) {
            $content = Get-Content $CONFIG_FILE -Raw
            
            # 更新 CONFIGURED_MODELS
            $modelsArrayStr = "@(" + ($script:CONFIGURED_MODELS | ForEach-Object { "`"$_`"" }) -join "," + ")"
            if ($content -match '(?m)^\s*\$CONFIGURED_MODELS\s*=') {
                $content = $content -replace '(?m)^\s*\$CONFIGURED_MODELS\s*=.*', "`$CONFIGURED_MODELS = $modelsArrayStr"
            } else {
                $content = $content.TrimEnd() + "`n`$CONFIGURED_MODELS = $modelsArrayStr"
            }
            
            # 删除已删除模型的 API 配置
            foreach ($deletedModel in $deletedModels) {
                $safeModelName = $deletedModel -replace '[^a-zA-Z0-9_]', '_'
                $content = $content -replace "(?m)^\s*\$MODEL_API_CONFIG_$safeModelName\s*=[^\r\n]*\r?\n", ''
            }
            
            $currentEncoding = [Console]::OutputEncoding
            if ($currentEncoding.CodePage -eq 936) {
                $saveEncoding = [System.Text.Encoding]::GetEncoding(936)
            } else {
                $saveEncoding = New-Object System.Text.UTF8Encoding $true
            }
            [System.IO.File]::WriteAllText($CONFIG_FILE, $content, $saveEncoding)
        }
        
        Write-Host ""
        Write-Host "✓ 已更新配置文件" -ForegroundColor Green
    }
    
    exit 0
}

# 预设指令: -setup 自动配置环境
if ($firstArg -eq "-setup" -or $firstArg -eq "setup") {
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "        CC 环境自动配置向导              " -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    
    # 创建 Profile
    if (!(Test-Path $PROFILE)) {
        Write-Host "[1/3] 创建 PowerShell Profile..." -ForegroundColor Yellow
        $profileDir = Split-Path $PROFILE -Parent
        if (!(Test-Path $profileDir)) {
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        }
        New-Item -ItemType File -Path $PROFILE -Force | Out-Null
        Write-Host "  ✓ 已创建" -ForegroundColor Green
    } else {
        Write-Host "[1/3] PowerShell Profile 已存在" -ForegroundColor Green
    }
    Write-Host ""
    
    # 添加 UTF-8 编码 + 包装函数
    Write-Host "[2/3] 配置 UTF-8 编码和参数修复..." -ForegroundColor Yellow
    
    $setupCode = @"

# ============================================
# CC 命令助手配置（由 cc -setup 自动生成）
# ============================================

# UTF-8 编码
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
`$OutputEncoding = [System.Text.Encoding]::UTF8
`$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# CC 包装函数（修复参数传递，正确处理以 - 开头的参数）
function cc {
    # 使用 $args 获取所有参数，避免 PowerShell 参数解析冲突
    if (`$args.Count -eq 0) {
        & "`$env:USERPROFILE\cc.ps1"
    } else {
        # 将所有参数作为字符串传递
        `$query = `$args -join " "
        & "`$env:USERPROFILE\cc.ps1" `$query
    }
}
"@
    
    $profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
    if (!$profileContent -or !($profileContent -match "CC 命令助手配置")) {
        Add-Content -Path $PROFILE -Value $setupCode
        Write-Host "  ✓ 已配置" -ForegroundColor Green
    } else {
        # 更新现有的包装函数（使用正则表达式替换整个 function cc 块）
        $newFunctionCode = ($setupCode -split "`n" | Select-Object -Skip 10 -Join "`n").Trim()
        if ($profileContent -match '(?s)function cc\s*\{[^}]+\}') {
            $profileContent = $profileContent -replace '(?s)function cc\s*\{[^}]+\}', $newFunctionCode
            [System.IO.File]::WriteAllText($PROFILE, $profileContent, [System.Text.Encoding]::UTF8)
            Write-Host "  ✓ 已更新包装函数" -ForegroundColor Green
        } else {
            Add-Content -Path $PROFILE -Value "`n$newFunctionCode"
            Write-Host "  ✓ 已添加包装函数" -ForegroundColor Green
        }
    }
    Write-Host ""
    
    # 立即应用
    Write-Host "[3/3] 应用配置到当前会话..." -ForegroundColor Yellow
    try {
        . $PROFILE
        Write-Host "  ✓ 已应用" -ForegroundColor Green
    } catch {
        Write-Host "  ⚠ 应用配置时出现警告: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  ℹ 请手动运行: . `$PROFILE" -ForegroundColor Gray
    }
    Write-Host ""
    
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host "           配置完成！                   " -ForegroundColor Green
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host ""
    Write-Host "现在可以直接使用中文了（无需引号）：" -ForegroundColor Gray
    Write-Host "  cc 你好" -ForegroundColor Cyan
    Write-Host "  cc 列出当前目录" -ForegroundColor Cyan
    Write-Host "  cc -r" -ForegroundColor Cyan
    Write-Host ""
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
    Write-Host "cc -setup" -NoNewline -ForegroundColor Green; Write-Host "      " -NoNewline; Write-Host "cc -u" -NoNewline -ForegroundColor Green; Write-Host "          " -NoNewline; Write-Host "cc -h" -ForegroundColor Green
    exit 0
}

# 获取用户输入（确保正确处理参数）
# 注意：如果第一个参数是预设指令，已经在上面处理过了，这里不应该再处理
# 但如果参数被包装函数拼接成了字符串（如 "-testapi"），需要重新解析
$userQuery = if ($args.Count -eq 1 -and $args[0] -is [string]) {
    $arg = $args[0]
    # 如果参数是单个字符串且以 - 开头，可能是预设指令，需要检查
    if ($arg -match '^-\w+') {
        # 尝试提取第一个参数（可能是预设指令）
        $parts = $arg -split '\s+', 2
        $possibleFirstArg = $parts[0]
        # 如果这个参数是预设指令，应该已经在上面处理过了
        # 这里只处理非预设指令的情况
        $arg
    } else {
        $arg
    }
} elseif ($args.Count -gt 0) {
    $args -join " "
} else {
    ""
}

# 如果输入为空，显示帮助信息
if ([string]::IsNullOrWhiteSpace($userQuery)) {
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
    Write-Host "cc -setup" -NoNewline -ForegroundColor Green; Write-Host "      " -NoNewline; Write-Host "cc -u" -NoNewline -ForegroundColor Green; Write-Host "          " -NoNewline; Write-Host "cc -h" -ForegroundColor Green
    exit 0
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
if ($script:MODE -eq "rest") {
    Safe-Write-Host -Message $cmd -ForegroundColor "Gray" -ShowEncodingHint
    exit 0
}

# 工作模式：清理命令并执行
$cmd = Sanitize-Command $cmd

if ([string]::IsNullOrWhiteSpace($cmd)) {
    Write-Host "ERROR: 空命令" -ForegroundColor Red
    exit 1
}

# 输出命令（使用安全输出函数处理 GBK 编码）
Safe-Write-Host -Message "> $cmd" -ForegroundColor "Gray" -ShowEncodingHint

$confirm = Read-Host "[y/n]"
if ([string]::IsNullOrWhiteSpace($confirm) -or $confirm -eq "y" -or $confirm -eq "yes") {
    Invoke-Expression $cmd
}

