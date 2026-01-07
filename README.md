# cc - AI 命令助手

基于 Ollama 的本地 AI 命令助手，用中文说需求，直接生成命令。

**当前版本：v1.5.0**

## 这是什么？

`cc` 是一个命令行工具，让你可以用中文描述想做什么，它帮你生成对应的命令。

> **性格设定**: cc 是个表面高冷实际上内心可爱热情的女孩子，就像程序员们一样——工作时专注高效（工作模式），休息时也喜欢聊聊天（休息模式）。

**解决的问题：**
- 记不住命令的具体参数（比如 `tar` 的解压参数总是记不清）
- 不知道用什么命令实现某个需求（想查端口占用，但不记得是 `netstat` 还是 `ss`）
- 经常需要搜索命令用法，打断工作流程
- Windows PowerShell 命令太长，每次都要查文档

**不能做什么：**
- 不能替代你学习命令行（它只是个辅助工具）
- 不能处理复杂的多步骤任务（只能生成单条命令）
- 不能保证 100% 准确（建议确认后再执行）
- 不能联网查询实时信息（它是本地运行的）

**适合谁：**
- 会用命令行，但记不住所有参数的人
- 想提高命令行效率的开发者
- 偶尔需要用命令但不想查文档的人

## ✨ 特性

- 🚀 中文自然语言转命令
- 🌱 **API 接入**：支持 Ollama / OpenAI / Anthropic / 自定义 API
- 💬 双模式：工作模式（命令生成）+ 休息模式（聊天）
- 🔄 智能模型管理：切换、安装、删除
- 🎨 自动编码检测（UTF-8/GBK）
- 📦 完整版本管理和更新系统
- 🖥️ 跨平台支持（Linux + Windows）

## 快速开始

### Linux

```bash
curl -fsSL https://raw.githubusercontent.com/jonas-pi/cc-helper/main/install.sh | bash
source ~/.bashrc
cc hello
```

**安装时可选：**
- **选项 1**：本地安装（Ollama + 本地模型，免费离线）
- **选项 2**：云端 API（DeepSeek/豆包/通义千问等，无需下载模型）

### Windows

在 PowerShell 中运行：

```powershell
irm https://raw.githubusercontent.com/jonas-pi/cc-helper/main/install.ps1 | iex
. $PROFILE
cc hello
```

**安装时可选：**
- **选项 1**：本地安装（Ollama + 本地模型，免费离线）
- **选项 2**：云端 API（DeepSeek/豆包/通义千问等，无需下载模型）

## 使用示例

### 工作模式（默认）

```bash
cc 查看当前目录
cc 哪些端口被占用
cc 查找最大的 10 个文件
cc 查看系统资源使用情况
```

### 休息模式

```bash
cc -r                    # 切换到休息模式
cc 今天天气怎么样？       # 可以聊天
cc 推荐一本书            # 可以对话
cc -w                    # 切换回工作模式
```

### Windows Shell 切换（仅 Windows）

```powershell
cc -shell                 # 查看并切换目标 Shell
# 选择 1 (PowerShell) 或 2 (CMD)

# PowerShell 模式示例
cc 获取当前时间          # 生成: Get-Date
cc 列出所有进程          # 生成: Get-Process

# CMD 模式示例  
cc 获取当前时间          # 生成: echo %date% %time%
cc 列出所有进程          # 生成: tasklist
```

**说明：**
- PowerShell 和 CMD 语法差异很大，cc 会根据目标 Shell 生成对应语法的命令
- 自动检测：在 CMD 中运行时自动使用 CMD 语法（实验性）
- 手动切换：`cc -shell` 可随时切换目标 Shell

## 预设命令

| 命令 | 说明 |
|------|------|
| `cc hello` | 显示版本和配置信息 |
| `cc list` | 列出所有可用模型 |
| `cc testapi` | 测试 API 连接状态 |
| `cc -h` / `cc -help` | 显示完整帮助信息 |
| `cc -u` | 更新到最新版本（带版本对比） |
| `cc -w` | 切换到工作模式（命令助手） |
| `cc -r` | 切换到休息模式（聊天） |
| `cc -stream` | 切换流式传输（逐字显示/一次性显示） |
| `cc -shell` | 切换目标 Shell（Windows：PowerShell/CMD） |
| `cc -change` | 切换使用的模型 |
| `cc -add` | 安装新模型 |
| `cc -del` | 删除模型 |
| `cc -fix` | 检测和修复编码问题 |
| `cc -config` | 配置 API（接入其他 AI 服务） |

## API 配置 - 成长空间

`cc` 可以接入市面上常见的 AI API，不再局限于本地：

```bash
cc -config
```

**支持的 API 类型：**

1. **Ollama**（默认）- 本地运行，完全免费
2. **OpenAI** - GPT-3.5/GPT-4，需要 API Key
3. **Anthropic** - Claude 3 系列，需要 API Key
4. **DeepSeek** - 国内高性价比，支持 deepseek-chat
5. **豆包/火山方舟** - 字节跳动，支持 doubao 系列
6. **通义千问/阿里云百炼** - 阿里云，支持 qwen-plus 等
7. **自定义** - 任何兼容 OpenAI API 格式的服务（Groq, Together AI 等）

**配置示例：**

```bash
# 切换到 OpenAI
cc -config
# 选择 2 → 输入 API Key → 输入模型名称

# 切换到 DeepSeek（国内推荐）
cc -config
# 选择 4 → 输入 API Key → 输入 deepseek-chat

# 切换到阿里云通义千问
cc -config
# 选择 6 → 输入 API Key → 输入 qwen-plus

# 现在 cc 已经使用新的 API 了
cc hello  # 查看当前配置
```

配置文件：Linux `~/.cc_config` | Windows `%USERPROFILE%\.cc_config.ps1`

---

## 模型管理（Ollama）

### 查看已安装的模型

```bash
cc hello
```

### 切换模型

```bash
cc -change
# 然后选择要切换到的模型
```

### 安装新模型

```bash
cc -add
# 从推荐列表中选择，或输入自定义模型名
```

### 删除模型

```bash
cc -del
# 选择要删除的模型（支持多选）
```

## 更新

### 自动更新（推荐）

```bash
cc -u
```

会显示：
- 当前版本
- 最新版本
- 更新日志
- 确认提示

### 强制更新（绕过缓存）

**Linux**:
```bash
curl -fsSL "https://raw.githubusercontent.com/jonas-pi/cc-helper/main/cc.sh?t=$(date +%s)" -o ~/cc.sh && chmod +x ~/cc.sh && cc hello
```

**Windows**:
```powershell
irm "https://raw.githubusercontent.com/jonas-pi/cc-helper/main/cc.ps1?t=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())" | Out-File "$env:USERPROFILE\cc.ps1" -Encoding UTF8; cc hello
```

## 卸载

### Linux

```bash
curl -fsSL https://raw.githubusercontent.com/jonas-pi/cc-helper/main/uninstall.sh | bash
source ~/.bashrc
```

### Windows

```powershell
irm https://raw.githubusercontent.com/jonas-pi/cc-helper/main/uninstall.ps1 | iex
```

## 系统要求

### Linux
- Linux 系统（支持树莓派）
- Bash 4.0+
- curl, jq
- 3GB+ RAM（推荐）
- 2GB+ 可用磁盘空间

### Windows
- Windows 10/11
- PowerShell 5.1+ 或 PowerShell Core
- winget（Windows 11 内置）
- 4GB+ RAM（推荐）
- 2GB+ 可用磁盘空间

## 推荐模型

### Linux
- **qwen2.5:0.5b** - 超轻量（400MB，3GB RAM）
- **qwen2.5:1.5b** - 日常推荐（1GB，4GB RAM）⭐
- **qwen2.5:3b** - 平衡之选（2GB，8GB RAM）
- **llama3.2:1b** - 轻量通用（1.2GB，4GB RAM）

### Windows
- **phi3.5** - PowerShell 最佳（2.2GB，8GB RAM）⭐
- **llama3.2:3b** - 通用平衡（2GB，8GB RAM）
- **qwen2.5:1.5b** - 轻量中文（1GB，4GB RAM）

## 故障排除

### 命令找不到

**Linux**:
```bash
source ~/.bashrc
```

**Windows**:
```powershell
. $PROFILE
```

### Ollama 连接失败

**Linux**:
```bash
ollama serve &
```

**Windows**:
```powershell
Start-Process ollama -ArgumentList "serve" -WindowStyle Hidden
```

### 模型未找到

```bash
cc -add
# 或手动安装
ollama pull qwen2.5:1.5b
```

### 更新失败

使用强制更新命令（见上方"强制更新"部分）

### 编码问题（Windows）

如果看到乱码，运行：
```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
```

## 更新日志

详见 [CHANGELOG.md](CHANGELOG.md)

## 许可证

MIT License

## 致谢

- [Ollama](https://ollama.com/) - 本地大模型运行环境
- [Qwen](https://github.com/QwenLM/Qwen) - 阿里云大语言模型
- [Phi-3.5](https://azure.microsoft.com/products/ai-services/phi-3) - 微软 AI 模型
- [Llama](https://llama.meta.com/) - Meta AI 模型

---

**提示**: 运行 `cc -help` 查看完整命令列表
