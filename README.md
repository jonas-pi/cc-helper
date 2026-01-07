# cc - AI 命令助手

一个基于 Ollama 大模型的 Linux 命令助手，可以通过中文描述自动生成并执行 shell 命令。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## ✨ 特性

- 🤖 **本地大模型**：使用 Ollama + qwen2.5:1.5b，无需联网，隐私安全
- ⚡ **极速启动**：纯 shell 脚本实现，启动速度快
- 🔒 **安全确认**：执行前确认，避免误操作
- 🎯 **智能理解**：准确理解中文需求，生成正确的命令
- 📦 **一键安装**：自动安装所有依赖，开箱即用
- 🗑️ **一键卸载**：完全清除所有相关文件和配置
- 🎨 **美观界面**：安装过程带有进度提示和加载动画

## 🚀 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/cc-helper/main/install.sh | bash
```

安装完成后：

```bash
source ~/.bashrc
```

## 📖 使用方法

### 基本用法

```bash
cc <中文需求>
```

### 示例

```bash
# 查看当前目录
cc 查看当前目录

# 查看端口占用
cc 哪些端口被占用

# 查找文件
cc 查找所有 .log 文件

# 查看系统信息
cc 查看系统信息

# 查看代理设置
cc 查看我的代理设置
```

## 📋 系统要求

- Linux 系统（Debian/Ubuntu/RHEL/CentOS/Arch 等）
- Bash 4.0+
- curl
- 至少 2GB 可用磁盘空间（用于模型文件）
- 网络连接（仅首次安装时需要）

## 🔧 安装说明

### 自动安装（推荐）

运行一键安装脚本，会自动完成：

1. ✅ 安装 Ollama
2. ✅ 拉取 qwen2.5:1.5b 模型
3. ✅ 安装依赖（jq）
4. ✅ 创建 cc.sh 脚本
5. ✅ 配置 PATH 和别名

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/cc-helper/main/install.sh | bash
source ~/.bashrc
```

### 手动安装

如果自动安装失败，可以手动安装：

```bash
# 1. 安装 Ollama
curl -fsSL https://ollama.com/install.sh | sh

# 2. 启动 Ollama 服务
ollama serve &

# 3. 拉取模型
ollama pull qwen2.5:1.5b

# 4. 安装 jq
sudo apt-get install -y jq  # Debian/Ubuntu
# 或
sudo yum install -y jq      # RHEL/CentOS

# 5. 下载并运行安装脚本
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/cc-helper/main/install.sh -o install.sh
bash install.sh
```

## ⚙️ 配置

### 修改模型

编辑 `~/cc.sh`，修改模型名称：

```bash
MODEL="qwen2.5:1.5b"  # 改为你想要的模型
```

然后拉取新模型：

```bash
ollama pull <新模型名>
```

### 修改 Ollama 地址

如果 Ollama 运行在其他地址：

```bash
OLLAMA_URL="http://127.0.0.1:11434/v1"  # 改为你的地址
```

## 🐛 故障排除

### 命令找不到 cc

```bash
source ~/.bashrc
# 或重新打开终端
```

### Ollama 连接失败

```bash
# 检查服务是否运行
pgrep ollama

# 启动服务
ollama serve &
```

### 模型未找到

```bash
# 查看已安装的模型
ollama list

# 重新拉取模型
ollama pull qwen2.5:1.5b
```

### jq 未安装

```bash
# Debian/Ubuntu
sudo apt-get install -y jq

# RHEL/CentOS
sudo yum install -y jq
```

## 📁 项目结构

```
cc-helper/
├── README.md      # 项目说明
├── install.sh     # 一键安装脚本
├── uninstall.sh   # 一键卸载脚本
├── LICENSE        # MIT 许可证
└── .gitignore     # Git 忽略文件
```

## 🗑️ 卸载

### 一键卸载（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/jonas-pi/cc-helper/main/uninstall.sh | bash
```

卸载脚本会自动清除：
- ✅ 脚本文件 (~/cc.sh, ~/bin/cc)
- ✅ 配置文件 (.bashrc 中的配置和别名)
- ✅ Ollama 模型 (qwen2.5:1.5b)
- ✅ Ollama 程序和数据目录
- ✅ 临时文件和日志

### 手动卸载

```bash
# 删除脚本
rm -f ~/cc.sh ~/bin/cc

# 从 .bashrc 中移除配置
sed -i '/# cc 命令助手配置/,+2d' ~/.bashrc
sed -i '/alias cc=/d' ~/.bashrc

# 删除模型
ollama rm qwen2.5:1.5b

# 卸载 Ollama（需要 sudo）
sudo rm -f $(which ollama)
rm -rf ~/.ollama

# 重新加载配置
source ~/.bashrc
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

MIT License

## 🙏 致谢

- [Ollama](https://ollama.com/) - 本地大模型运行环境
- [Qwen](https://github.com/QwenLM/Qwen) - 大语言模型
