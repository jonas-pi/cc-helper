# cc 命令助手 PowerShell 脚本

# Ollama 配置
$OLLAMA_URL = "http://127.0.0.1:11434/v1"
$MODEL = "phi3.5"
$MODE = "work"  # work: 工作模式（只输出命令）, rest: 休息模式（可以聊天）

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

# 获取命令或回复
function Get-AICommand {
    param([string]$query)
    
    # 根据模式设置不同的提示词
    $prompt = ""
    $systemMsg = ""
    
    if ($MODE -eq "rest") {
        # 休息模式：可以聊天
        $prompt = @"
请用友好、轻松的语气回复用户。可以聊天、解答问题、提供建议。

用户说：
$query

回复：
"@
        $systemMsg = "你是一个友好的AI助手，喜欢和用户聊天交流。"
    } else {
        # 工作模式：只输出命令
        $prompt = @"
Convert the following Chinese request into a single PowerShell command.
Output ONLY the command, without any explanation, markdown, code blocks, or extra text.

Request in Chinese: $query

PowerShell Command:
"@
        $systemMsg = "You are a PowerShell assistant. Output only the PowerShell command, nothing else."
    }
    
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
    Write-Host "(｡･ω･｡) cc v1.0" -ForegroundColor Gray
    Write-Host ""
    
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
    
    # 列出所有已安装的模型
    $modelList = ollama list 2>$null
    if ($modelList) {
        $models = $modelList | Select-Object -Skip 1 | ForEach-Object {
            ($_ -split '\s+')[0]
        } | Where-Object { $_ -ne "" }
        
        if ($models.Count -gt 0) {
            Write-Host ""
            Write-Host "已安装的模型:" -ForegroundColor Gray
            foreach ($model in $models) {
                if ($model -eq $MODEL) {
                    Write-Host "  • " -NoNewline
                    Write-Host "$model" -ForegroundColor Green
                } else {
                    Write-Host "  • $model"
                }
            }
        }
    }
    
    Write-Host ""
    Write-Host "准备好了~ 有什么可以帮你的吗？" -ForegroundColor Gray
    exit 0
}

# 预设指令: -w 工作模式
if ($firstArg -eq "-w" -or $firstArg -eq "work") {
    $scriptPath = "$env:USERPROFILE\cc.ps1"
    $content = Get-Content $scriptPath -Raw
    $content = $content -replace '^\$MODE = ".*"', '$MODE = "work"'
    
    $currentEncoding = [Console]::OutputEncoding
    if ($currentEncoding.CodePage -eq 936) {
        $saveEncoding = [System.Text.Encoding]::GetEncoding(936)
    } else {
        $saveEncoding = New-Object System.Text.UTF8Encoding $true
    }
    [System.IO.File]::WriteAllText($scriptPath, $content, $saveEncoding)
    
    Write-Host "已切换到工作模式" -ForegroundColor Cyan -NoNewline
    Write-Host " - 专注命令，高效执行" -ForegroundColor Gray
    exit 0
}

# 预设指令: -r 休息模式
if ($firstArg -eq "-r" -or $firstArg -eq "rest" -or $firstArg -eq "chat") {
    $scriptPath = "$env:USERPROFILE\cc.ps1"
    $content = Get-Content $scriptPath -Raw
    $content = $content -replace '^\$MODE = ".*"', '$MODE = "rest"'
    
    $currentEncoding = [Console]::OutputEncoding
    if ($currentEncoding.CodePage -eq 936) {
        $saveEncoding = [System.Text.Encoding]::GetEncoding(936)
    } else {
        $saveEncoding = New-Object System.Text.UTF8Encoding $true
    }
    [System.IO.File]::WriteAllText($scriptPath, $content, $saveEncoding)
    
    Write-Host "已切换到休息模式" -ForegroundColor Magenta -NoNewline
    Write-Host " - 放松一下，聊聊天吧~" -ForegroundColor Gray
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

# 预设指令: -change 切换模型
if ($firstArg -eq "-change" -or $firstArg -eq "change") {
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
    
    # 更新脚本中的 MODEL 变量
    $scriptPath = "$env:USERPROFILE\cc.ps1"
    $content = Get-Content $scriptPath -Raw
    $content = $content -replace '^\$MODEL = ".*"', "`$MODEL = `"$selected`""
    
    # 保存时使用正确的编码
    $currentEncoding = [Console]::OutputEncoding
    if ($currentEncoding.CodePage -eq 936) {
        $saveEncoding = [System.Text.Encoding]::GetEncoding(936)
    } else {
        $saveEncoding = New-Object System.Text.UTF8Encoding $true
    }
    [System.IO.File]::WriteAllText($scriptPath, $content, $saveEncoding)
    
    Write-Host "已切换到: $selected" -ForegroundColor Gray
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
if ($args.Count -lt 1 -or $firstArg -eq "-h" -or $firstArg -eq "--help") {
    Write-Host "用法: cc <中文需求>" -ForegroundColor Gray
    Write-Host "示例: cc 我在哪个目录" -ForegroundColor Gray
    Write-Host "" -ForegroundColor Gray
    Write-Host "预设指令:" -ForegroundColor Gray
    Write-Host "  cc hello     - 显示版本和模型信息" -ForegroundColor Gray
    Write-Host "  cc -u        - 更新脚本" -ForegroundColor Gray
    Write-Host "  cc -w        - 切换到工作模式（命令助手）" -ForegroundColor Gray
    Write-Host "  cc -r        - 切换到休息模式（聊天）" -ForegroundColor Gray
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

# 休息模式：直接输出回复
if ($MODE -eq "rest") {
    Write-Host $cmd -ForegroundColor Gray
    exit 0
}

# 工作模式：清理命令并执行
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
