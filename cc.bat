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

