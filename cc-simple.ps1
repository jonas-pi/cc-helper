# cc 命令助手 PowerShell 脚本（简化版，解决编码问题）

$OLLAMA_URL = "http://127.0.0.1:11434/v1"
$MODEL = "qwen2.5:1.5b"

if ($args.Count -lt 1) {
    Write-Host "用法: cc <中文需求>" -ForegroundColor Red
    exit 1
}

$userQuery = $args -join " "

# 调试模式（设置为 $true 查看匹配过程）
$DEBUG = $false

if ($DEBUG) {
    Write-Host "[DEBUG] 原始查询: $userQuery" -ForegroundColor Gray
    Write-Host "[DEBUG] 查询长度: $($userQuery.Length)" -ForegroundColor Gray
}

# 先尝试智能推断（避免模型编码问题）
# 使用字符编码无关的方法：检查字节模式
$inferredCmd = ""

# 将查询转换为字节，检查是否包含特定中文字符的 UTF-8 编码
$queryBytes = [System.Text.Encoding]::UTF8.GetBytes($userQuery)
$queryUtf8 = [System.Text.Encoding]::UTF8.GetString($queryBytes)

if ($DEBUG) {
    Write-Host "[DEBUG] UTF-8 查询: $queryUtf8" -ForegroundColor Gray
}

# 使用多种匹配方式
if ($userQuery -match '目录' -or $userQuery -match '路径' -or $userQuery -match '位置' -or $userQuery -match '在哪' -or
    $userQuery -match 'mulu' -or $userQuery -match 'lujing' -or $userQuery -match 'weizhi' -or $userQuery -match 'zainali') {
    $inferredCmd = "Get-Location"
    if ($DEBUG) { Write-Host "[DEBUG] 匹配: 目录/路径" -ForegroundColor Green }
} elseif ($userQuery -match '文件' -or $userQuery -match 'wenjian' -or $userQuery -match 'ls' -or $userQuery -match '列表') {
    $inferredCmd = "Get-ChildItem"
    if ($DEBUG) { Write-Host "[DEBUG] 匹配: 文件" -ForegroundColor Green }
} elseif ($userQuery -match '进程' -or $userQuery -match '程序' -or $userQuery -match 'jincheng' -or $userQuery -match 'chengxu' -or $userQuery -match '运行中') {
    $inferredCmd = "Get-Process"
    if ($DEBUG) { Write-Host "[DEBUG] 匹配: 进程" -ForegroundColor Green }
} elseif ($userQuery -match '服务' -or $userQuery -match 'fuwu') {
    $inferredCmd = "Get-Service"
    if ($DEBUG) { Write-Host "[DEBUG] 匹配: 服务" -ForegroundColor Green }
} elseif ($userQuery -match '日期' -or $userQuery -match '时间' -or $userQuery -match 'riqi' -or $userQuery -match 'shijian' -or $userQuery -match '现在几点') {
    $inferredCmd = "Get-Date"
    if ($DEBUG) { Write-Host "[DEBUG] 匹配: 日期/时间" -ForegroundColor Green }
} elseif ($userQuery -match '网络' -or $userQuery -match 'IP' -or $userQuery -match '地址' -or $userQuery -match 'wangluo' -or $userQuery -match 'dizhi') {
    $inferredCmd = "Get-NetIPAddress"
    if ($DEBUG) { Write-Host "[DEBUG] 匹配: 网络/IP" -ForegroundColor Green }
} elseif ($userQuery -match '端口' -or $userQuery -match '监听' -or $userQuery -match '占用' -or $userQuery -match 'duankou' -or $userQuery -match 'jianting' -or $userQuery -match 'zhanyong') {
    $inferredCmd = "Get-NetTCPConnection | Where-Object State -eq 'Listen'"
    if ($DEBUG) { Write-Host "[DEBUG] 匹配: 端口" -ForegroundColor Green }
} elseif ($userQuery -match '磁盘' -or $userQuery -match '空间' -or $userQuery -match '容量' -or $userQuery -match 'cipan' -or $userQuery -match 'kongjian' -or $userQuery -match 'rongliang') {
    $inferredCmd = "Get-PSDrive -PSProvider FileSystem"
    if ($DEBUG) { Write-Host "[DEBUG] 匹配: 磁盘" -ForegroundColor Green }
}

if ($DEBUG -and -not $inferredCmd) {
    Write-Host "[DEBUG] 未匹配到任何关键词" -ForegroundColor Yellow
}

# 如果有推断结果，直接使用
if ($inferredCmd) {
    Write-Host ""
    Write-Host "> AI 建议: $inferredCmd" -ForegroundColor Green
    Write-Host "  (智能推断)" -ForegroundColor DarkGray
    Write-Host ""
    
    $confirm = Read-Host "确认执行该命令吗？(y/Enter 执行, n 退出)"
    if ([string]::IsNullOrWhiteSpace($confirm) -or $confirm -eq "y" -or $confirm -eq "yes") {
        Write-Host ""
        Write-Host "正在执行: $inferredCmd" -ForegroundColor Yellow
        Write-Host ""
        Invoke-Expression $inferredCmd
    } else {
        Write-Host "已取消执行。"
    }
    exit 0
}

# 如果没有推断结果，尝试调用模型
$prompt = "将以下中文需求转换为一条 Windows PowerShell 命令，只输出命令，不要任何解释：

$userQuery"

$systemMsg = "你是一个命令转换助手。只输出命令，不要解释。"

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

try {
    $response = Invoke-RestMethod -Uri "$OLLAMA_URL/chat/completions" `
        -Method Post `
        -ContentType "application/json" `
        -Body $jsonBody `
        -ErrorAction Stop

    if ($response.choices -and $response.choices.Count -gt 0 -and $response.choices[0].message.content) {
        $content = $response.choices[0].message.content.Trim()
        
        # 简单清理
        $content = $content -replace '```.*', '' -replace '```', ''
        $content = ($content -split "`n")[0].Trim()
        
        # 检查是否有效
        if ($content -and $content -notmatch '^\?+$' -and ([regex]::Matches($content, '\?')).Count -lt 10) {
            Write-Host ""
            Write-Host "> AI 建议: $content" -ForegroundColor Green
            Write-Host ""
            
            $confirm = Read-Host "确认执行该命令吗？(y/Enter 执行, n 退出)"
            if ([string]::IsNullOrWhiteSpace($confirm) -or $confirm -eq "y" -or $confirm -eq "yes") {
                Write-Host ""
                Write-Host "正在执行: $content" -ForegroundColor Yellow
                Write-Host ""
                Invoke-Expression $content
            } else {
                Write-Host "已取消执行。"
            }
        } else {
            Write-Host "错误: 模型返回了无效命令（编码问题）" -ForegroundColor Red
            Write-Host "建议: 使用更具体的关键词，如 '目录'、'文件'、'进程' 等" -ForegroundColor Yellow
        }
    } else {
        Write-Host "错误: 模型未返回内容" -ForegroundColor Red
    }
} catch {
    Write-Host "错误: $($_.Exception.Message)" -ForegroundColor Red
}

