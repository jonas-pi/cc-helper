# cc 命令助手 PowerShell 脚本
# 编码: UTF-8 with BOM

# 强制使用 UTF-8 编码
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# Ollama 配置
$OLLAMA_URL = "http://127.0.0.1:11434/v1"
$MODEL = "qwen2.5:1.5b"

# 调试模式
$DEBUG = $false

if ($args.Count -lt 1) {
    Write-Host "用法: cc <中文需求>" -ForegroundColor Red
    Write-Host "示例: cc 查看当前目录" -ForegroundColor Yellow
    exit 1
}

$userQuery = $args -join " "

if ($DEBUG) {
    Write-Host "[DEBUG] 查询: $userQuery" -ForegroundColor Gray
}

# 智能推断命令（使用 Contains 而不是正则匹配，更可靠）
function Get-InferredCommand {
    param([string]$query)
    
    $q = $query.ToLower()
    
    # 目录/路径相关
    if ($q.Contains("目录") -or $q.Contains("路径") -or $q.Contains("位置") -or 
        $q.Contains("在哪") -or $q.Contains("当前") -or $q.Contains("哪里")) {
        return "Get-Location"
    }
    
    # 文件列表相关
    if ($q.Contains("文件") -or $q.Contains("列表") -or $q.Contains("列出") -or 
        $q.Contains("查看") -or $q.Contains("显示")) {
        return "Get-ChildItem"
    }
    
    # 进程相关
    if ($q.Contains("进程") -or $q.Contains("程序") -or $q.Contains("运行")) {
        return "Get-Process"
    }
    
    # 服务相关
    if ($q.Contains("服务")) {
        return "Get-Service"
    }
    
    # 时间日期相关
    if ($q.Contains("时间") -or $q.Contains("日期") -or $q.Contains("几点") -or 
        $q.Contains("现在") -or $q.Contains("今天")) {
        return "Get-Date"
    }
    
    # 网络相关
    if ($q.Contains("网络") -or $q.Contains("ip") -or $q.Contains("地址") -or 
        $q.Contains("网卡")) {
        return "Get-NetIPAddress"
    }
    
    # 端口相关
    if ($q.Contains("端口") -or $q.Contains("监听") -or $q.Contains("占用")) {
        return "Get-NetTCPConnection | Where-Object State -eq 'Listen'"
    }
    
    # 磁盘相关
    if ($q.Contains("磁盘") -or $q.Contains("空间") -or $q.Contains("容量") -or 
        $q.Contains("硬盘") -or $q.Contains("分区")) {
        return "Get-PSDrive -PSProvider FileSystem"
    }
    
    # 内存相关
    if ($q.Contains("内存") -or $q.Contains("内存使用")) {
        return "Get-WmiObject Win32_OperatingSystem | Select-Object TotalVisibleMemorySize,FreePhysicalMemory"
    }
    
    # 系统信息
    if ($q.Contains("系统") -or $q.Contains("版本") -or $q.Contains("信息")) {
        return "Get-ComputerInfo | Select-Object WindowsProductName,WindowsVersion,OsArchitecture"
    }
    
    return $null
}

# 先尝试智能推断
$inferredCmd = Get-InferredCommand $userQuery

if ($inferredCmd) {
    if ($DEBUG) {
        Write-Host "[DEBUG] 智能推断命令: $inferredCmd" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "> AI 建议: " -ForegroundColor Green -NoNewline
    Write-Host $inferredCmd -ForegroundColor White
    Write-Host "  (智能推断)" -ForegroundColor DarkGray
    Write-Host ""
    
    $confirm = Read-Host "确认执行该命令吗？(y/Enter 执行, n 退出)"
    if ([string]::IsNullOrWhiteSpace($confirm) -or $confirm -eq "y" -or $confirm -eq "yes") {
        Write-Host ""
        Write-Host "正在执行: $inferredCmd" -ForegroundColor Yellow
        Write-Host ""
        try {
            Invoke-Expression $inferredCmd
        } catch {
            Write-Host "执行错误: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "已取消执行。"
    }
    exit 0
}

# 如果没有推断结果，尝试调用模型
if ($DEBUG) {
    Write-Host "[DEBUG] 未匹配到关键词，调用模型..." -ForegroundColor Yellow
}

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
        -ContentType "application/json; charset=utf-8" `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($jsonBody)) `
        -ErrorAction Stop

    if ($response.choices -and $response.choices.Count -gt 0 -and $response.choices[0].message.content) {
        $content = $response.choices[0].message.content.Trim()
        
        if ($DEBUG) {
            Write-Host "[DEBUG] 模型返回: $content" -ForegroundColor Magenta
        }
        
        # 简单清理
        $content = $content -replace '```powershell', '' -replace '```ps1', '' -replace '```bash', '' -replace '```shell', '' -replace '```', ''
        $content = ($content -split "`n")[0].Trim()
        
        # 检查是否包含大量问号（编码问题）
        $questionCount = ($content.ToCharArray() | Where-Object { $_ -eq '?' }).Count
        
        if ($content -and $questionCount -lt ($content.Length * 0.3)) {
            Write-Host ""
            Write-Host "> AI 建议: " -ForegroundColor Green -NoNewline
            Write-Host $content -ForegroundColor White
            Write-Host ""
            
            $confirm = Read-Host "确认执行该命令吗？(y/Enter 执行, n 退出)"
            if ([string]::IsNullOrWhiteSpace($confirm) -or $confirm -eq "y" -or $confirm -eq "yes") {
                Write-Host ""
                Write-Host "正在执行: $content" -ForegroundColor Yellow
                Write-Host ""
                try {
                    Invoke-Expression $content
                } catch {
                    Write-Host "执行错误: $($_.Exception.Message)" -ForegroundColor Red
                }
            } else {
                Write-Host "已取消执行。"
            }
        } else {
            Write-Host ""
            Write-Host "错误: 模型返回了无效命令（可能是编码问题）" -ForegroundColor Red
            Write-Host ""
            Write-Host "提示: 请使用更具体的关键词，例如：" -ForegroundColor Yellow
            Write-Host "  - cc 查看当前目录" -ForegroundColor Cyan
            Write-Host "  - cc 列出文件" -ForegroundColor Cyan
            Write-Host "  - cc 查看进程" -ForegroundColor Cyan
            Write-Host "  - cc 查看服务" -ForegroundColor Cyan
            Write-Host "  - cc 查看时间" -ForegroundColor Cyan
            Write-Host "  - cc 查看端口" -ForegroundColor Cyan
        }
    } else {
        Write-Host "错误: 模型未返回内容" -ForegroundColor Red
    }
} catch {
    Write-Host "错误: $($_.Exception.Message)" -ForegroundColor Red
    if ($DEBUG) {
        Write-Host "[DEBUG] 详细错误: $($_.Exception)" -ForegroundColor Red
    }
}

