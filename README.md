# cc - AI 命令助手

基于 Ollama 的 Linux 命令助手，通过中文描述自动生成并执行 shell 命令。

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/jonas-pi/cc-helper/main/install.sh | bash
source ~/.bashrc
```

## 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/jonas-pi/cc-helper/main/uninstall.sh | bash
source ~/.bashrc
```

## 使用

```bash
cc 查看当前目录
cc 哪些端口被占用
cc 查找所有 .log 文件
cc 查看系统信息
```

## 系统要求

- Linux 系统
- Bash 4.0+
- curl
- 至少 2GB 可用磁盘空间

## 配置

编辑 `~/cc.sh` 修改模型：

```bash
MODEL="qwen2.5:1.5b"  # 改为你想要的模型
```

然后拉取新模型：

```bash
ollama pull <新模型名>
```

## 故障排除

**命令找不到 cc**
```bash
source ~/.bashrc
```

**Ollama 连接失败**
```bash
ollama serve &
```

**模型未找到**
```bash
ollama pull qwen2.5:1.5b
```

## 许可证

MIT License

## 致谢

- [Ollama](https://ollama.com/) - 本地大模型运行环境
- [Qwen](https://github.com/QwenLM/Qwen) - 大语言模型
