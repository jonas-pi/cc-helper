# cc 命令助手 Windows 安装脚本
# 功能：安装 Ollama、拉取模型、配置 cc 命令

# 错误处理
$ErrorActionPreference = "Stop"

# 颜色输出函数
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) {
        Write-Output $args
    }
    $host.UI.RawUI.ForegroundColor = $fc
}

function Write-Red($text) { Write-ColorOutput Red $text }
function Write-Green($text) { Write-ColorOutput Green $text }
function Write-Yellow($text) { Write-ColorOutput Yellow $text }
function Write-Blue($text) { Write-ColorOutput Blue $text }

# 配置
$OLLAMA_MODEL = "phi3.5"
$OLLAMA_URL = "http://127.0.0.1:11434"
$CC_SCRIPT_PATH = "$env:USERPROFILE\cc.ps1"
$BIN_DIR = "$env:USERPROFILE\bin"

# 显示铭牌
Write-ColorOutput Cyan @"
  ██████╗ ██████╗     ██╗  ██╗███████╗██╗     ██████╗ ███████╗██████╗ 
 ██╔════╝██╔════╝     ██║  ██║██╔════╝██║     ██╔══██╗██╔════╝██╔══██╗
 ██║     ██║    █████╗███████║█████╗  ██║     ██████╔╝█████╗  ██████╔╝
 ██║     ██║    ╚════╝██╔══██║██╔══╝  ██║     ██╔═══╝ ██╔══╝  ██╔══██╗
 ╚██████╗╚██████╗     ██║  ██║███████╗███████╗██║     ███████╗██║  ██║
  ╚═════╝ ╚═════╝     ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝     ╚══════╝╚═╝  ╚═╝

      AI 命令助手 - 基于 Ollama 的智能命令生成工具
"@
Write-Output ""
Write-Blue "========================================"
Write-Blue "  正在安装 cc 命令助手..."
Write-Blue "========================================"
Write-Output ""

# 检查管理员权限（不需要，但可以提示）
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Yellow "提示: 某些操作可能需要管理员权限"
}

# 1. 安装 Ollama
Write-Yellow "[1/4] 检查并安装 Ollama..."
if (Get-Command ollama -ErrorAction SilentlyContinue) {
    Write-Green "✓ Ollama 已安装"
    ollama --version 2>$null
} else {
    Write-Yellow "正在安装 Ollama..."
    
    # 尝试使用 winget 安装
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Yellow "使用 winget 安装 Ollama..."
        try {
            winget install Ollama.Ollama --silent --accept-package-agreements --accept-source-agreements
            Write-Green "✓ Ollama 安装成功"
            # 刷新 PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        } catch {
            Write-Red "✗ winget 安装失败，尝试手动安装"
            Write-Yellow "请访问 https://ollama.com/download 下载并安装 Ollama"
            Write-Yellow "安装完成后重新运行此脚本"
            exit 1
        }
    } else {
        Write-Yellow "未找到 winget，请手动安装 Ollama"
        Write-Yellow "1. 访问 https://ollama.com/download"
        Write-Yellow "2. 下载并安装 Ollama"
        Write-Yellow "3. 重新运行此脚本"
        exit 1
    }
}

# 启动 Ollama 服务（如果未运行）
Write-Yellow "检查 Ollama 服务状态..."
$ollamaProcess = Get-Process -Name ollama -ErrorAction SilentlyContinue
if (-not $ollamaProcess) {
    Write-Yellow "启动 Ollama 服务..."
    Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
    Start-Sleep -Seconds 3
    Write-Green "✓ Ollama 服务已启动"
} else {
    Write-Green "✓ Ollama 服务运行中"
}

# 检查 Ollama 是否可访问（最多重试 5 次）
Write-Yellow "检查 Ollama 连接..."
$OLLAMA_OK = $false
for ($i = 1; $i -le 5; $i++) {
    try {
        $response = Invoke-WebRequest -Uri "$OLLAMA_URL/api/tags" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        Write-Green "✓ Ollama 服务运行正常"
        $OLLAMA_OK = $true
        break
    } catch {
        if ($i -lt 5) {
            Write-Yellow "等待服务响应... ($i/5)"
            Start-Sleep -Seconds 1
        }
    }
}

if (-not $OLLAMA_OK) {
    Write-Yellow "⚠ Ollama 服务未响应，但继续安装..."
    Write-Yellow "安装完成后请手动启动 Ollama"
}
Write-Output ""

# 2. 拉取模型
Write-Yellow "[2/4] 检查并拉取模型 $OLLAMA_MODEL..."
$modelList = ollama list 2>$null
if ($modelList -match $OLLAMA_MODEL) {
    Write-Green "✓ 模型 $OLLAMA_MODEL 已存在"
} else {
    Write-Yellow "正在拉取模型 $OLLAMA_MODEL..."
    Write-Yellow "（这可能需要一些时间，请耐心等待）"
    ollama pull $OLLAMA_MODEL
    if ($LASTEXITCODE -eq 0) {
        Write-Green "✓ 模型拉取成功"
    } else {
        Write-Red "✗ 模型拉取失败"
        exit 1
    }
}
Write-Output ""

# 3. 检查依赖（curl 在 Windows 10+ 中已内置）
Write-Yellow "[3/4] 检查依赖..."
if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
    Write-Green "✓ curl 已安装"
} else {
    Write-Red "✗ curl 未找到，Windows 10+ 应内置 curl"
    exit 1
}
Write-Output ""

# 4. 创建 cc.ps1 脚本
Write-Yellow "[4/4] 创建 cc.ps1 脚本..."

$ccScriptContent = @'
# cc 命令助手 PowerShell 脚本

# Ollama 配置
$OLLAMA_URL = "http://127.0.0.1:11434/v1"
$MODEL = "qwen2.5:1.5b"

# 清理命令输出
function Sanitize-Command {
    param([string]$cmd)
    if ([string]::IsNullOrWhiteSpace($cmd)) {
        return ""
    }
    # 移除代码块标记（包括 PowerShell、bash、shell 等）
    $cmd = $cmd -replace '```powershell', '' -replace '```ps1', '' -replace '```bash', '' -replace '```shell', '' -replace '```', ''
    # 移除首尾空白和换行
    $cmd = $cmd.Trim()
    # 移除末尾的反斜杠
    $cmd = $cmd -replace '\\$', ''
    
    # 只取第一行
    $lines = $cmd -split "`n", 2
    $cmd = $lines[0].Trim()
    
    # 移除可能的提示词残留（更全面的匹配）
    $cmd = $cmd -replace '^Windows Power.*?:', '' -replace '^只输出命令.*?:', '' -replace '^命令.*?:', '' -replace '^将中文需求.*?:', ''
    $cmd = $cmd -replace '^你是一个.*?:', '' -replace '^转换助手.*?:', '' -replace '^Windows.*?:', ''
    
    # 移除可能的冒号和后续文本（如果模型返回了 "命令: xxx" 格式）
    if ($cmd -match '^[^:]+:\s*(.+)$') {
        $cmd = $matches[1].Trim()
    }
    
    # 如果命令包含大量中文字符或问号（可能是编码问题），尝试提取命令部分
    $chineseCount = ([regex]::Matches($cmd, '[\u4e00-\u9fff]')).Count
    $questionMarkCount = ([regex]::Matches($cmd, '\?')).Count
    
    if ($chineseCount -gt 5 -or $questionMarkCount -gt 3) {
        # 尝试提取第一个看起来像命令的部分
        # 匹配以字母开头的命令（可能包含连字符、下划线、点号）
        if ($cmd -match '([A-Za-z][A-Za-z0-9\-_\.]*\s+[^\u4e00-\u9fff\n]*)') {
            $potentialCmd = $matches[1].Trim()
            if ($potentialCmd.Length -gt 0 -and $potentialCmd.Length -lt $cmd.Length) {
                $cmd = $potentialCmd
            }
        }
        # 如果还是包含中文字符，尝试提取最后一个看起来像命令的部分
        if ($cmd -match '.*?([A-Za-z][A-Za-z0-9\-_\.]*\s*.*?)$') {
            $potentialCmd = $matches[1].Trim()
            if ($potentialCmd.Length -gt 0) {
                $cmd = $potentialCmd
            }
        }
    }
    
    # 再次清理首尾空白
    $cmd = $cmd.Trim()
    return $cmd
}

# 获取命令（重命名以避免与 PowerShell 内置 cmdlet 冲突）
function Get-AICommand {
    param([string]$query)
    
    # 构建提示词（简化，避免模型返回提示词本身）
    $prompt = @"
将中文需求转换为一条可直接执行的 Windows PowerShell 命令。
只输出命令，不要解释、不要 Markdown、不要占位符、不要代码块标记。
如果缺少参数，使用最常见的默认命令。
注意：代理设置通常指 HTTP/HTTPS 代理（环境变量 http_proxy, https_proxy），不是 DNS 设置。

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
            # 确保返回的是字符串，并处理可能的编码问题
            if ($content -is [string]) {
                $content = $content.Trim()
            } else {
                $content = $content.ToString().Trim()
            }
            
            # 如果内容包含中文字符且看起来像是提示词，尝试提取命令部分
            # 常见的 PowerShell 命令模式
            $commonCommands = @('Get-Location', 'Get-ChildItem', 'Set-Location', 'Get-Process', 
                               'Get-Service', 'Get-Content', 'Select-String', 'Where-Object',
                               'pwd', 'ls', 'dir', 'cd', 'cat', 'type', 'findstr', 'grep')
            
            foreach ($cmdPattern in $commonCommands) {
                if ($content -match $cmdPattern) {
                    # 提取从命令开始到行尾的内容
                    $match = [regex]::Match($content, "$cmdPattern.*")
                    if ($match.Success) {
                        $extracted = $match.Value.Trim()
                        # 只取第一行
                        $extracted = ($extracted -split "`n")[0].Trim()
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
'@

$ccScriptContent | Out-File -FilePath $CC_SCRIPT_PATH -Encoding UTF8
Write-Green "✓ cc.ps1 脚本创建成功"
Write-Output ""

# 5. 创建 bin 目录并设置 PATH
Write-Yellow "配置 PATH 和别名..."

# 创建 bin 目录
if (-not (Test-Path $BIN_DIR)) {
    New-Item -ItemType Directory -Path $BIN_DIR -Force | Out-Null
}

# 创建 cc.bat 包装器（用于在 CMD 中调用）
$ccBatContent = @"
@echo off
powershell.exe -ExecutionPolicy Bypass -File "$CC_SCRIPT_PATH" %*
"@
$ccBatPath = "$BIN_DIR\cc.bat"
$ccBatContent | Out-File -FilePath $ccBatPath -Encoding ASCII
Write-Green "✓ 创建 $ccBatPath"

# 更新用户 PATH 环境变量
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$BIN_DIR*") {
    $newPath = "$userPath;$BIN_DIR"
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Green "✓ 已添加 $BIN_DIR 到 PATH"
    # 更新当前会话的 PATH
    $env:Path = "$env:Path;$BIN_DIR"
} else {
    Write-Green "✓ PATH 已包含 $BIN_DIR"
}

# 创建 PowerShell 配置文件（如果不存在）
$profilePath = $PROFILE.CurrentUserAllHosts
$profileDir = Split-Path $profilePath -Parent
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

# 添加 cc 函数到 PowerShell 配置文件
$ccFunction = @"

# cc 命令助手函数
function cc {
    & "$CC_SCRIPT_PATH" `$args
}
"@

if (Test-Path $profilePath) {
    $profileContent = Get-Content $profilePath -Raw
    if ($profileContent -notmatch "function cc") {
        Add-Content -Path $profilePath -Value $ccFunction
        Write-Green "✓ 已添加 cc 函数到 PowerShell 配置文件"
    } else {
        Write-Green "✓ cc 函数已存在于 PowerShell 配置文件"
    }
} else {
    $ccFunction | Out-File -FilePath $profilePath -Encoding UTF8
    Write-Green "✓ 已创建 PowerShell 配置文件并添加 cc 函数"
}
Write-Output ""

# 创建 cc.bat 批处理文件（用于 CMD）
Write-Yellow "创建 CMD 批处理文件..."
$ccBatContent = @'
@echo off
REM cc 命令助手 - PowerShell 包装器
REM 支持在 CMD 和 PowerShell 中使用

chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion

if "%~1"=="" (
    echo 用法: cc ^<中文需求^>
    echo 示例: cc 查看当前目录
    exit /b 1
)

REM 收集所有参数
set "args=%*"

REM 调用 PowerShell 脚本
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\cc.ps1" %args%

exit /b %ERRORLEVEL%
'@

$ccBatPath = "$BIN_DIR\cc.bat"
[System.IO.File]::WriteAllText($ccBatPath, $ccBatContent, [System.Text.Encoding]::ASCII)
Write-Green "✓ 已创建 $ccBatPath"
Write-Output ""

# 完成
Write-Output ""
Write-Output ""
Write-ColorOutput Cyan "╔════════════════════════════════════════════════════════════════╗"
Write-ColorOutput Cyan "║                                                                ║"
Write-ColorOutput Cyan "║                    ✓ 安装完成！                                ║"
Write-ColorOutput Cyan "║                                                                ║"
Write-ColorOutput Cyan "╚════════════════════════════════════════════════════════════════╝"
Write-Output ""
Write-Output ""
Write-ColorOutput Yellow "╔════════════════════════════════════════════════════════════════╗"
Write-ColorOutput Yellow "║                                                                ║"
Write-ColorOutput Yellow "║              ✓ cc 命令已就绪！                                  ║"
Write-ColorOutput Yellow "║                                                                ║"
Write-ColorOutput Yellow "║  可在以下环境中使用：                                           ║"
Write-ColorOutput Green   "║    • PowerShell                                               ║"
Write-ColorOutput Green   "║    • CMD（命令提示符）                                         ║"
Write-ColorOutput Yellow "║                                                                ║"
Write-ColorOutput Yellow "║  使用示例：                                                    ║"
Write-ColorOutput Green   "║     cc hello           # 测试安装                              ║"
Write-ColorOutput Yellow "║                                                                ║"
Write-ColorOutput Yellow "║  更新脚本：                                                    ║"
Write-ColorOutput Green   "║     cc -u              # 更新到最新版本                        ║"
Write-ColorOutput Yellow "║                                                                ║"
Write-ColorOutput Yellow "╚════════════════════════════════════════════════════════════════╝"
Write-Output ""
Write-Output ""
Write-Yellow "配置信息："
Write-Output "  - 模型: $OLLAMA_MODEL"
Write-Output "  - PowerShell 脚本: $CC_SCRIPT_PATH"
Write-Output "  - CMD 批处理: $ccBatPath"
Write-Output "  - 已添加到 PATH: $BIN_DIR"
Write-Output ""
Write-Yellow "故障排除："
Write-Output "  - 如果找不到 cc 命令，请重新打开终端窗口"
Write-Output "  - PowerShell 中可直接使用，CMD 中通过批处理调用"
Write-Output "  - 如果遇到权限问题，以管理员身份运行终端"
Write-Output ""

