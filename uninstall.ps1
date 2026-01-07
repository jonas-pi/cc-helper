# cc 命令助手 Windows 卸载脚本

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

Write-Blue "========================================"
Write-Blue "  卸载 cc 命令助手"
Write-Blue "========================================"
Write-Output ""

# 配置
$CC_SCRIPT_PATH = "$env:USERPROFILE\cc.ps1"
$BIN_DIR = "$env:USERPROFILE\bin"
$OLLAMA_MODEL = "qwen2.5:1.5b"

# 1. 删除脚本文件
Write-Yellow "[1/6] 删除脚本文件..."
if (Test-Path $CC_SCRIPT_PATH) {
    Start-Sleep -Milliseconds 500
    Remove-Item -Path $CC_SCRIPT_PATH -Force
    Write-Green "✓ 已删除 $CC_SCRIPT_PATH"
} else {
    Write-Yellow "  $CC_SCRIPT_PATH 不存在"
}

$ccBatPath = "$BIN_DIR\cc.bat"
if (Test-Path $ccBatPath) {
    Start-Sleep -Milliseconds 300
    Remove-Item -Path $ccBatPath -Force
    Write-Green "✓ 已删除 $ccBatPath"
} else {
    Write-Yellow "  $ccBatPath 不存在"
}
Write-Output ""

# 2. 从 PowerShell 配置文件中移除函数
Write-Yellow "[2/6] 从 PowerShell 配置文件中移除配置..."
$profilePath = $PROFILE.CurrentUserAllHosts
if (Test-Path $profilePath) {
    Start-Sleep -Milliseconds 300
    # 备份配置文件
    $backupPath = "$profilePath.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item -Path $profilePath -Destination $backupPath -Force
    Write-Green "✓ 已备份 PowerShell 配置文件"
    
    Start-Sleep -Milliseconds 300
    # 读取并移除 cc 函数
    $profileContent = Get-Content $profilePath -Raw
    if ($profileContent -match "(?s)# cc 命令助手函数.*?function cc.*?\n}") {
        $profileContent = $profileContent -replace "(?s)# cc 命令助手函数.*?function cc.*?\n}", ""
        $profileContent | Out-File -FilePath $profilePath -Encoding UTF8 -NoNewline
        Write-Green "✓ 已移除 cc 函数"
    } else {
        Write-Yellow "  cc 函数不存在于配置文件中"
    }
} else {
    Write-Yellow "  PowerShell 配置文件不存在"
}
Write-Output ""

# 3. 从 PATH 中移除 bin 目录
Write-Yellow "[3/6] 从 PATH 中移除配置..."
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -like "*$BIN_DIR*") {
    Start-Sleep -Milliseconds 300
    $newPath = ($userPath -split ';' | Where-Object { $_ -ne $BIN_DIR }) -join ';'
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Green "✓ 已从 PATH 中移除 $BIN_DIR"
} else {
    Write-Yellow "  PATH 中不包含 $BIN_DIR"
}
Write-Output ""

# 4. 删除模型
Write-Yellow "[4/6] 删除 Ollama 模型..."
if (Get-Command ollama -ErrorAction SilentlyContinue) {
    # 确保 Ollama 服务正在运行（列出模型需要）
    $ollamaProcess = Get-Process -Name ollama -ErrorAction SilentlyContinue
    if (-not $ollamaProcess) {
        Write-Yellow "启动 Ollama 服务以列出模型..."
        Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    
    # 列出所有模型
    $modelOutput = ollama list 2>&1
    if ($modelOutput) {
        $models = $modelOutput | Select-Object -Skip 1 | ForEach-Object {
            ($_ -split '\s+')[0]
        } | Where-Object { $_ -ne "" }
        
        if ($models.Count -gt 0) {
            Write-Green "已安装的模型："
            for ($i = 0; $i -lt $models.Count; $i++) {
                Write-Output "$($i + 1). $($models[$i])"
            }
            Write-Output ""
            Write-Yellow "请选择要删除的模型（输入序号，多个用空格分隔，或输入 'all' 删除全部，直接回车跳过）："
            $selection = Read-Host
            
            if ($selection) {
                if ($selection -eq "all" -or $selection -eq "ALL") {
                    # 删除所有模型
                    foreach ($model in $models) {
                        Write-Yellow "正在删除模型 $model..."
                        try {
                            ollama rm $model 2>&1 | Out-Null
                        if ($LASTEXITCODE -eq 0) {
                            Write-Green "✓ $model 已删除"
                        } else {
                            Write-Red "✗ $model 删除失败"
                            }
                        } catch {
                            Write-Red "✗ $model 删除失败: $($_.Exception.Message)"
                        }
                        Start-Sleep -Milliseconds 500
                    }
                } else {
                    # 删除选定的模型
                    $numbers = $selection -split '\s+' | Where-Object { $_ -match '^\d+$' }
                    foreach ($num in $numbers) {
                        $index = [int]$num - 1
                        if ($index -ge 0 -and $index -lt $models.Count) {
                            $model = $models[$index]
                            Write-Yellow "正在删除模型 $model..."
                            try {
                                ollama rm $model 2>&1 | Out-Null
                            } catch {
                                # 忽略错误
                            }
                            if ($LASTEXITCODE -eq 0) {
                                Write-Green "✓ $model 已删除"
                            } else {
                                Write-Red "✗ $model 删除失败"
                            }
                            Start-Sleep -Milliseconds 500
                        }
                    }
                }
            } else {
                Write-Yellow "跳过模型删除"
            }
        } else {
            Write-Yellow "  未找到已安装的模型"
        }
    } else {
        Write-Yellow "  未找到已安装的模型"
    }
    
    # 停止 Ollama 服务
    $ollamaProcess = Get-Process -Name ollama -ErrorAction SilentlyContinue
    if ($ollamaProcess) {
        Write-Yellow "停止 Ollama 服务..."
        Stop-Process -Name ollama -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Write-Green "✓ Ollama 服务已停止"
    }
} else {
    Write-Yellow "  Ollama 未安装，跳过"
}
Write-Output ""

# 5. 卸载 Ollama
Write-Yellow "[5/6] 卸载 Ollama..."

# 停止所有 Ollama 进程
$ollamaProcesses = Get-Process -Name ollama -ErrorAction SilentlyContinue
if ($ollamaProcesses) {
    Write-Yellow "停止 Ollama 服务进程..."
    Stop-Process -Name ollama -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Green "✓ Ollama 进程已停止"
    Start-Sleep -Milliseconds 500
}

# 查找 Ollama 安装位置
$ollamaPaths = @(
    "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe",
    "$env:ProgramFiles\Ollama\ollama.exe",
    "$env:ProgramFiles(x86)\Ollama\ollama.exe"
)

$ollamaFound = $false
foreach ($path in $ollamaPaths) {
    if (Test-Path $path) {
        Write-Yellow "发现 Ollama: $path"
        Start-Sleep -Milliseconds 300
        try {
            # 尝试使用 winget 卸载
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                winget uninstall Ollama.Ollama --silent 2>&1 | Out-Null
                Write-Green "✓ 已通过 winget 卸载 Ollama"
                $ollamaFound = $true
                break
            }
        } catch {
            Write-Yellow "  需要手动卸载 Ollama"
            Write-Yellow "  请通过 设置 > 应用 > 应用和功能 卸载 Ollama"
        }
    }
}

# 删除 Ollama 数据目录
$ollamaDataDirs = @(
    "$env:USERPROFILE\.ollama",
    "$env:LOCALAPPDATA\Ollama"
)

foreach ($dir in $ollamaDataDirs) {
    if (Test-Path $dir) {
        Write-Yellow "发现数据目录: $dir"
        Start-Sleep -Milliseconds 300
        try {
            Remove-Item -Path $dir -Recurse -Force -ErrorAction Stop
            Write-Green "✓ 已删除 $dir"
        } catch {
            Write-Yellow "  无法删除 $dir，可能正在使用中"
            Write-Yellow "  请手动删除或重启后删除"
        }
    }
}

if (-not $ollamaFound -and -not (Get-Process -Name ollama -ErrorAction SilentlyContinue)) {
    Write-Yellow "  Ollama 未找到或已卸载"
}
Write-Output ""

# 6. 清理 bin 目录（如果为空）
Write-Yellow "[6/6] 清理目录..."
if (Test-Path $BIN_DIR) {
    Start-Sleep -Milliseconds 300
    $items = Get-ChildItem -Path $BIN_DIR -ErrorAction SilentlyContinue
    if ($items.Count -eq 0) {
        Remove-Item -Path $BIN_DIR -Force -ErrorAction SilentlyContinue
        Write-Green "✓ 已删除空目录 $BIN_DIR"
    } else {
        Write-Yellow "  $BIN_DIR 目录不为空，保留"
    }
}
Write-Output ""

# 完成
Write-Blue "========================================"
Write-Green "卸载完成！"
Write-Blue "========================================"
Write-Output ""
Write-Yellow "下一步："
Write-Output "1. 重新打开 PowerShell 或运行以下命令："
Write-Host "   . `$PROFILE" -ForegroundColor Green
Write-Output ""
Write-Output "2. 或者在新的终端窗口中测试"
Write-Output ""
Write-Yellow "已清除的内容："
Write-Output "  ✓ 脚本文件 ($CC_SCRIPT_PATH, $ccBatPath)"
Write-Output "  ✓ PowerShell 配置文件中的函数"
Write-Output "  ✓ PATH 环境变量配置"
Write-Output "  ✓ Ollama 模型 ($OLLAMA_MODEL)"
Write-Output "  ✓ Ollama 程序和数据目录（如已卸载）"
Write-Output ""
Write-Yellow "注意："
Write-Output "- PowerShell 配置文件备份已保存为: $profilePath.backup.*"
Write-Output "- 如需重新安装，请运行安装脚本"
Write-Output ""

