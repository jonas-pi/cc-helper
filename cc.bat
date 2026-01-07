@echo off
REM cc 命令助手 - CMD 批处理包装器
REM 自动检测编码并调用 PowerShell 脚本

chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion

if "%~1"=="" (
    echo 用法: cc ^<中文需求^>
    echo 示例: cc 查看当前目录
    exit /b 1
)

REM 收集所有参数
set "args=%*"

REM 调用 PowerShell 脚本，使用 UTF-8 编码
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { $OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; & '%USERPROFILE%\cc.ps1' %args% }"

exit /b %ERRORLEVEL%

