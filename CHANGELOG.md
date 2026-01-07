# CC 命令助手 - 更新日志

## v0.2.0 (2026-01-07) - 流式传输支持

### ✨ 重大新功能：流式传输
- **新增 `cc -stream` 命令**：切换流式传输模式
  - 开启后，AI 响应将逐字显示（打字机效果）
  - 关闭后，响应一次性显示（默认）
  - 配置持久化到 `~/.cc_config` 或 `.cc_config.ps1`

### 🎯 使用方式
```bash
# 开启流式传输
cc -stream  # 切换状态

# 切换到休息模式并聊天
cc -r
cc 讲一个故事  # 看到逐字显示效果（Linux 完整支持）

# 查看当前配置
cc hello  # 显示流式传输状态
```

### 📋 功能说明
- **Linux/macOS (Bash)**：✅ 完整支持流式传输
  - 使用 `curl -N --no-buffer` 实时接收 SSE 流
  - 逐行解析 `data:` 格式
  - 实时逐字显示响应内容
- **Windows (PowerShell)**：⚠️ 部分支持
  - 已添加 `cc -stream` 命令和配置
  - API 请求中已启用 `stream: true`
  - 显示逻辑暂为一次性输出（流式解析功能开发中）

### ⚙️ 技术细节
- 流式传输仅在**休息模式** (`cc -r`) 下生效
- 工作模式需要完整命令，不支持流式传输
- 使用 Server-Sent Events (SSE) 协议
- 灰色显示流式内容，最终返回完整文本

### 🔧 配置示例
**Linux `~/.cc_config`:**
```bash
STREAM="true"  # 开启流式传输
MODE="rest"    # 休息模式
```

**Windows `%USERPROFILE%\.cc_config.ps1`:**
```powershell
$STREAM = $true  # 开启流式传输
$MODE = "rest"   # 休息模式
```

---

## v0.1.5 (2026-01-07) - 增强 fix 功能

### ✨ 新增功能
- **`cc -fix` 新增强制更新选项**
  - 编码检测完成后，询问用户是否立即强制更新
  - 一键完成编码修复 + 版本更新
  - 自动备份当前版本
  - 确保编码修复后使用最新版本

### 使用场景
```bash
# Linux
cc -fix
# 1. 检测编码
# 2. 显示字符测试
# 3. 询问是否强制更新 [y/n]

# Windows
cc -fix
# 1. 检测编码
# 2. 可选切换编码 [1/2/n]
# 3. 询问是否强制更新 [y/n]
```

### 优势
- 修复编码问题后无需手动运行 `cc -u`
- 确保编码和版本同步更新
- 减少用户操作步骤

---

## v0.1.4 (2026-01-07) - 安全性与编码修复

### 🔒 安全性改进
- **更新 .gitignore**：确保用户配置文件（包含 API Key）不会被提交到 git
  - 添加 `.cc_config` (Linux)
  - 添加 `.cc_config.ps1` (Windows)
  - 防止 API Key 泄露

### ✨ 新增功能
- **新增 `cc -fix` 命令**：编码检测和修复工具
  - Linux: 检测 LANG 和 locale 编码，提供 UTF-8 配置建议
  - Windows: 检测 CodePage，提供 UTF-8/GBK 切换选项
  - 交互式编码切换和测试
  - 显示当前使用的字符集（表情、列表符号等）

### ⚡ 性能优化
- **curl 请求优化**：添加 `--compressed` 标志启用 gzip 压缩
  - 减少数据传输量
  - 加快 API 响应速度（如果服务器支持压缩）

### 📝 文档更新
- README 添加 `cc -fix` 命令说明
- 帮助信息 (`cc -h`) 添加 `cc -fix` 命令

---

## v0.1.3 (2026-01-07) - 修复模式切换

### 🐛 关键 Bug 修复
- **修复 `cc -w` 和 `cc -r` 模式切换不生效的问题**
  - 问题原因：脚本修改的是 `cc.sh`/`cc.ps1` 文件本身，但 `MODE` 配置实际从 `~/.cc_config` 加载
  - 解决方案：改为修改配置文件 `~/.cc_config` (Linux) 或 `%USERPROFILE%\.cc_config.ps1` (Windows)
  - 现在 `cc -r` 切换到休息模式后，可以正常聊天了
  - 现在 `cc -w` 切换回工作模式后，只输出命令

### 测试结果
```bash
# Linux
cc -r           # 切换到休息模式
cc 你好          # 返回聊天回复（而不是命令）
cc -w           # 切换回工作模式
cc 你好          # 返回 echo "你好" 命令
```

---

## v0.1.2 (2026-01-07) - 稳定性修复

### 🐛 关键 Bug 修复

**Linux (Bash):**
- **修复 DeepSeek/豆包/通义千问 等云端 API 无法连接的问题**
  - 问题原因：`curl` 命令中 `$auth_header` 变量无法正确展开带引号的 header
  - 解决方案：直接在 `curl` 命令中使用 `-H "Authorization: Bearer $API_KEY"`
  - 影响范围：`cc testapi` 和 `cc <命令>` 的 API 调用
- **修复 HTTP 状态码 000 错误**：现在可以正确发送 Authorization header
- **符合 DeepSeek API 官方文档标准**：[https://api-docs.deepseek.com/zh-cn/](https://api-docs.deepseek.com/zh-cn/)

**Windows (PowerShell):**
- **修复 `[System.Object[]]` 返回问题**
  - 问题原因：API 返回的 `content` 可能是数组类型
  - 解决方案：增强类型检查，单元素数组取第一个元素，多元素数组用换行符连接
  - 确保返回值强制转换为 `[string]` 类型
- **提升稳定性**：更可靠的字符串类型转换逻辑

### 版本说明
- 版本号调整为 0.1.x，反映项目处于早期阶段
- 专注于修复核心功能，确保基本可用性

---

## v0.9.0 (2026-01-07) - 已废弃

### 重大变化
- 🔄 版本号降级为测试版 (0.9.0)，以反映当前的稳定性状态

### 新增功能
- ✨ **新增 `cc testapi` 命令**：诊断 API 连接问题，提供详细的错误诊断和解决建议
- ✨ **简化 `cc help` 输出**：只列出命令清单，不再显示冗长的描述和示例

### Bug 修复
- 🐛 **修复 PowerShell 变量作用域问题**：Check-And-Select-Model 现在使用 `$script:` 前缀访问全局变量
- 🐛 **修复命令返回 [System.Object[]] 的问题**：改进参数处理和返回值类型检查
- 🐛 **修复云端 API 模型检查**：使用云端 API 时不再错误检查 Ollama 本地模型

### 已知问题
- ⚠️ Windows 用户在更新后，如果仍然看到 "注意: 使用模型 xxx" 错误，请尝试：
  1. 删除旧的 cc.ps1：`Remove-Item $env:USERPROFILE\cc.ps1`
  2. 重新下载：`irm https://raw.githubusercontent.com/jonas-pi/cc-helper/main/install.ps1 | iex`
  3. 重新配置 API：`cc -config`

