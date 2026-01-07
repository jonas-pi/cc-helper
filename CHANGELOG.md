# CC 命令助手 - 更新日志

## v0.9.1 (2026-01-07) - 关键修复

### 🐛 关键 Bug 修复
- **修复 DeepSeek/豆包/通义千问 等云端 API 无法连接的问题**
  - 问题原因：`curl` 命令中 `$auth_header` 变量无法正确展开带引号的 header
  - 解决方案：直接在 `curl` 命令中使用 `-H "Authorization: Bearer $API_KEY"`
  - 影响范围：`cc testapi` 和 `cc <命令>` 的 API 调用
- **修复 HTTP 状态码 000 错误**：现在可以正确发送 Authorization header
- **符合 DeepSeek API 官方文档标准**：[https://api-docs.deepseek.com/zh-cn/](https://api-docs.deepseek.com/zh-cn/)

### 技术说明
Bash 中直接使用变量展开带引号的字符串（如 `$auth_header="-H \"Authorization: Bearer $API_KEY\""`）会导致引号被当作字符串的一部分，而不是 shell 的语法。正确的做法是直接写在命令中或使用 `eval`。

---

## v0.9.0 (2026-01-07) - 测试版

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

