# cc 命令助手 Windows 安装脚本
# 功能：安装 Ollama、拉取模型、配置 cc 命令

# 错误处理
$ErrorActionPreference = "Stop"

# 颜色输出函数
function Write-ColorOutput($ForegroundColor, $Text) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($Text) {
        Write-Host $Text
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

# 询问安装方式
Write-Yellow "选择安装方式:"
Write-Host "  " -NoNewline; Write-Host "1." -ForegroundColor Green -NoNewline; Write-Host " 本地安装 (Ollama + 本地模型，免费离线)"
Write-Host "  " -NoNewline; Write-Host "2." -ForegroundColor Green -NoNewline; Write-Host " 云端 API (DeepSeek/豆包/通义千问等，需要 API Key)"
Write-Output ""
Write-Host "请选择 [1/2] (默认: 1): " -ForegroundColor Yellow -NoNewline
$installChoice = Read-Host
if ([string]::IsNullOrWhiteSpace($installChoice)) {
    $installChoice = "1"
}

if ($installChoice -eq "2") {
    # 跳过 Ollama 安装，直接配置云端 API
    Write-Output ""
    Write-Green "✓ 已选择云端 API 模式"
    Write-Output ""
    
    # 直接下载 cc.ps1 脚本
    Write-Yellow "[1/2] 下载 cc.ps1 脚本..."
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.Encoding = [System.Text.Encoding]::UTF8
        $scriptUrl = "https://raw.githubusercontent.com/jonas-pi/cc-helper/main/cc.ps1"
        $content = $webClient.DownloadString($scriptUrl)
        
        # 检测控制台编码并保存
        $currentEncoding = [Console]::OutputEncoding
        if ($currentEncoding.CodePage -eq 936) {
            $saveEncoding = [System.Text.Encoding]::GetEncoding(936)
        } else {
            $saveEncoding = New-Object System.Text.UTF8Encoding $true
        }
        
        [System.IO.File]::WriteAllText($CC_SCRIPT_PATH, $content, $saveEncoding)
        Write-Green "  ✓ cc.ps1 脚本下载成功"
    } catch {
        Write-Red "✗ cc.ps1 脚本下载失败: $($_.Exception.Message)"
        exit 1
    }
    Write-Output ""
    
    # 配置 PowerShell Profile
    Write-Yellow "[2/2] 配置环境..."
    $profilePath = $PROFILE
    if (-not (Test-Path $profilePath)) {
        New-Item -Path $profilePath -ItemType File -Force | Out-Null
    }
    
    $functionDef = @"
function cc {
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$CC_SCRIPT_PATH" `$args
}
"@
    
    if (-not (Select-String -Path $profilePath -Pattern "function cc" -Quiet)) {
        Add-Content -Path $profilePath -Value $functionDef
        Write-Green "  ✓ 已添加 cc 函数到 PowerShell Profile"
    }
    Write-Output ""
    
    # 完成提示
    Write-Green "========================================"
    Write-Green "  ✓ cc 命令助手安装完成！"
    Write-Green "========================================"
    Write-Output ""
    Write-Yellow "下一步:"
    Write-Host "  1. 刷新环境: " -NoNewline; Write-Host ". `$PROFILE" -ForegroundColor Green
    Write-Host "  2. 配置 API: " -NoNewline; Write-Host "cc -config" -ForegroundColor Green
    Write-Host "  3. 查看帮助: " -NoNewline; Write-Host "cc -help" -ForegroundColor Green
    Write-Output ""
    exit 0
}

# 1. 安装 Ollama (本地模式)
Write-Output ""
Write-Green "✓ 已选择本地 Ollama 模式"
Write-Output ""
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

# 2. 选择并拉取模型
Write-Yellow "[2/4] 选择 Ollama 模型..."
Write-Output ""

# 获取系统信息
$totalRamGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
$cpuCores = (Get-CimInstance Win32_Processor).NumberOfCores
Write-Green "系统配置:"
Write-Output "  RAM: $totalRamGB GB"
Write-Output "  CPU 核心: $cpuCores"
Write-Output ""

# 模型列表（按 PowerShell 支持度排序）
$modelList = @(
    @{Name="phi3.5"; Size="2.2GB"; RamNeed=8; Desc="微软3.8B模型，PS命令最佳，代码生成强"; PsSupport=10},
    @{Name="llama3.2:3b"; Size="2GB"; RamNeed=8; Desc="Meta平衡，多模态支持，PS兼容性佳"; PsSupport=9},
    @{Name="llama3.2:1b"; Size="1.2GB"; RamNeed=4; Desc="Meta轻量，边缘优化，PS支持良好"; PsSupport=9},
    @{Name="qwen2.5:1.5b"; Size="1GB"; RamNeed=4; Desc="轻量快速，中文优秀，PS可用"; PsSupport=7},
    @{Name="qwen2.5:3b"; Size="2GB"; RamNeed=8; Desc="中等性能，中文顶尖，PS可用"; PsSupport=7},
    @{Name="qwen2.5:0.5b"; Size="400MB"; RamNeed=3; Desc="超轻量，中文不错，低配应急"; PsSupport=6},
    @{Name="qwen2.5:7b"; Size="4.7GB"; RamNeed=16; Desc="高性能，128K上下文，中文顶尖"; PsSupport=7}
)

# 根据 RAM 和 PowerShell 支持度给出推荐
Write-Green "可用模型 (按 PowerShell 支持度排序):"
$recommended = 0
$bestScore = 0
for ($i = 0; $i -lt $modelList.Count; $i++) {
    $model = $modelList[$i]
    $num = $i + 1
    
    # 计算推荐分数 (PowerShell 支持度 * RAM 是否满足)
    $score = 0
    if ($totalRamGB -ge $model.RamNeed) {
        $score = $model.PsSupport
        if ($score -gt $bestScore) {
            $bestScore = $score
            $recommended = $num
        }
    }
    
    # 判断是否可用
    if ($totalRamGB -ge $model.RamNeed) {
        Write-Host "  $num. " -NoNewline
        Write-Host "$($model.Name)" -ForegroundColor Green -NoNewline
        Write-Host " - $($model.Size) - $($model.Desc) (需要 $($model.RamNeed)GB RAM)"
    } else {
        Write-Host "  $num. $($model.Name) - $($model.Size) - $($model.Desc) (需要 $($model.RamNeed)GB RAM) " -NoNewline
        Write-Host "[配置不足]" -ForegroundColor Red
    }
}
Write-Output ""

if ($recommended -gt 0) {
    Write-Host "根据您的系统配置 (${totalRamGB}GB RAM) 和 " -NoNewline
    Write-Host "PowerShell 支持度" -ForegroundColor Cyan -NoNewline
    Write-Host "，推荐: " -NoNewline
    Write-Host "选项 $recommended" -ForegroundColor Green
} else {
    Write-Yellow "警告: 系统 RAM 较低，建议选择最轻量的模型"
    $recommended = 1
}
Write-Output ""

Write-Yellow "请选择要安装的模型（输入序号，多个用空格分隔，或直接回车使用推荐）:"
Write-Host "" -NoNewline
$selection = Read-Host

# 如果用户直接回车，使用推荐
if ([string]::IsNullOrWhiteSpace($selection)) {
    $selection = $recommended.ToString()
}

# 解析用户选择
$selectedModels = @()
$numbers = $selection -split '\s+' | Where-Object { $_ -match '^\d+$' }
foreach ($num in $numbers) {
    $index = [int]$num - 1
    if ($index -ge 0 -and $index -lt $modelList.Count) {
        $selectedModels += $modelList[$index].Name
    }
}

if ($selectedModels.Count -eq 0) {
    Write-Red "错误: 没有选择有效的模型"
    exit 1
}

# 如果选择了多个模型，让用户选择默认使用的
$defaultModel = $selectedModels[0]
if ($selectedModels.Count -gt 1) {
    Write-Output ""
    Write-Yellow "您选择了多个模型，请选择默认使用的模型:"
    for ($i = 0; $i -lt $selectedModels.Count; $i++) {
        Write-Output "  $($i + 1). $($selectedModels[$i])"
    }
    Write-Host "" -NoNewline
    $defaultChoice = Read-Host
    if ($defaultChoice -match '^\d+$') {
        $defaultIndex = [int]$defaultChoice - 1
        if ($defaultIndex -ge 0 -and $defaultIndex -lt $selectedModels.Count) {
            $defaultModel = $selectedModels[$defaultIndex]
        }
    }
}

$OLLAMA_MODEL = $defaultModel
Write-Output ""
Write-Green "将安装以下模型: $($selectedModels -join ', ')"
Write-Green "默认使用: $OLLAMA_MODEL"
Write-Output ""

# 拉取选中的模型
foreach ($model in $selectedModels) {
    $existingModels = ollama list 2>$null
    if ($existingModels -match [regex]::Escape($model)) {
        Write-Green "✓ ${model} 已存在"
    } else {
        Write-Yellow "正在拉取模型 ${model}..."
        ollama pull $model
        if ($LASTEXITCODE -eq 0) {
            Write-Green "✓ ${model} 拉取完成"
        } else {
            Write-Red "✗ ${model} 拉取失败"
        }
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

# 4. 下载并配置 cc.ps1 脚本
Write-Yellow "[4/4] 下载并配置 cc.ps1 脚本..."
try {
    $webClient = New-Object System.Net.WebClient
    $webClient.Encoding = [System.Text.Encoding]::UTF8
    $scriptUrl = "https://raw.githubusercontent.com/jonas-pi/cc-helper/main/cc.ps1"
    $ccScriptContent = $webClient.DownloadString($scriptUrl)
    
    # 替换默认模型为用户选择的模型（如果脚本中有硬编码的默认模型）
    # 注意：新版本的 cc.ps1 已经有自动检测模型功能，但我们可以设置一个合理的默认值
    # 使用更精确的正则表达式匹配，确保只替换默认配置行
    $ccScriptContent = $ccScriptContent -replace '(?m)^(\s*\$MODEL\s*=\s*)"[^"]+"', "`$1`"$OLLAMA_MODEL`""
    
    # 检测控制台编码并保存
    $currentEncoding = [Console]::OutputEncoding
    if ($currentEncoding.CodePage -eq 936) {
        $saveEncoding = [System.Text.Encoding]::GetEncoding(936)
    } else {
        $saveEncoding = New-Object System.Text.UTF8Encoding $true
    }
    
    [System.IO.File]::WriteAllText($CC_SCRIPT_PATH, $ccScriptContent, $saveEncoding)
    Write-Green "✓ cc.ps1 脚本下载并配置成功"
    
    # 创建或更新配置文件，确保使用正确的模型
    $CONFIG_FILE = "$env:USERPROFILE\.cc_config.ps1"
    $configContent = @"
# cc 命令助手配置文件
# 此文件由安装脚本自动生成

`$MODEL = "$OLLAMA_MODEL"
`$API_TYPE = "ollama"
`$OLLAMA_URL = "http://127.0.0.1:11434/v1"
`$MODE = "work"
"@
    
    [System.IO.File]::WriteAllText($CONFIG_FILE, $configContent, $saveEncoding)
    Write-Green "✓ 配置文件已更新为使用模型: $OLLAMA_MODEL"
} catch {
    Write-Red "✗ cc.ps1 脚本下载失败: $($_.Exception.Message)"
    Write-Yellow "尝试使用本地模板..."
    
    # 如果下载失败，使用简化的本地模板（包含自动检测功能提示）
    $fallbackScript = @"
# cc 命令助手 PowerShell 脚本
# 注意: 这是简化版本，建议从 GitHub 下载完整版本

# Ollama 配置
`$OLLAMA_URL = "http://127.0.0.1:11434/v1"
`$MODEL = "$OLLAMA_MODEL"

Write-Host "ERROR: 请从 GitHub 下载完整版本的 cc.ps1" -ForegroundColor Red
Write-Host "URL: https://raw.githubusercontent.com/jonas-pi/cc-helper/main/cc.ps1" -ForegroundColor Yellow
exit 1
"@
    [System.IO.File]::WriteAllText($CC_SCRIPT_PATH, $fallbackScript, [System.Text.Encoding]::UTF8)
    Write-Yellow "⚠ 已创建占位脚本，请手动下载完整版本"
}
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

# 4. 安装 Tab 补全功能
Write-Yellow "[4/4] 安装 Tab 补全功能..."
$completionFile = "$env:USERPROFILE\.cc-completion.ps1"
try {
    $webClient = New-Object System.Net.WebClient
    $webClient.Encoding = [System.Text.Encoding]::UTF8
    $completionContent = $webClient.DownloadString("https://raw.githubusercontent.com/jonas-pi/cc-helper/main/cc-completion.ps1")
    [System.IO.File]::WriteAllText($completionFile, $completionContent, [System.Text.Encoding]::UTF8)
    
    # 添加到 PowerShell Profile（如果还没有）
    if (!(Test-Path $PROFILE)) {
        New-Item -ItemType File -Path $PROFILE -Force | Out-Null
    }
    
    $profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
    if (!$profileContent -or !($profileContent -match "\.cc-completion\.ps1")) {
        Add-Content -Path $PROFILE -Value "`n# cc 命令补全"
        Add-Content -Path $PROFILE -Value "if (Test-Path `"$completionFile`") { . `"$completionFile`" }"
        Write-Green "  ✓ 已安装 Tab 补全功能"
    } else {
        Write-Green "  ✓ Tab 补全已存在"
    }
} catch {
    Write-Yellow "  ⚠ Tab 补全安装失败（不影响使用）"
}
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
Write-ColorOutput Yellow "║  可在以下环境中使用（支持 Tab 补全）：                          ║"
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

