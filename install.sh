#!/bin/bash

# cc 命令助手安装脚本
# 功能：安装 Ollama、拉取模型、配置 cc 命令

set -e

# 错误处理函数
error_exit() {
    echo -e "${RED}✗ 错误: $1${NC}" >&2
    exit 1
}

# 颜色定义
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

# 配置
OLLAMA_MODEL="qwen2.5:1.5b"
OLLAMA_URL="http://127.0.0.1:11434"
CC_SCRIPT_PATH="$HOME/cc.sh"
BIN_DIR="$HOME/bin"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  cc 命令助手安装脚本${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 检查是否为 root（不应该用 root 运行）
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}错误: 请不要使用 root 用户运行此脚本${NC}"
    exit 1
fi

# 1. 安装 Ollama
echo -e "${YELLOW}[1/4] 检查并安装 Ollama...${NC}"
if command -v ollama &> /dev/null; then
    echo -e "${GREEN}✓ Ollama 已安装${NC}"
    ollama --version
else
    echo -e "${YELLOW}正在安装 Ollama...${NC}"
    curl -fsSL https://ollama.com/install.sh | sh
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Ollama 安装成功${NC}"
    else
        echo -e "${RED}✗ Ollama 安装失败${NC}"
        exit 1
    fi
fi

# 启动 Ollama 服务（如果未运行）
echo -e "${YELLOW}检查 Ollama 服务状态...${NC}"
if ! pgrep -x ollama > /dev/null; then
    echo -e "${YELLOW}启动 Ollama 服务...${NC}"
    ollama serve > /dev/null 2>&1 &
    sleep 3
    # 再次检查是否启动成功
    if ! pgrep -x ollama > /dev/null; then
        echo -e "${YELLOW}等待 Ollama 服务启动...${NC}"
        sleep 2
    fi
fi

# 检查 Ollama 是否可访问（最多重试 3 次）
echo -e "${YELLOW}检查 Ollama 连接...${NC}"
for i in {1..3}; do
    if curl -s "$OLLAMA_URL/api/tags" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Ollama 服务运行正常${NC}"
        break
    else
        if [ $i -eq 3 ]; then
            echo -e "${RED}✗ 无法连接到 Ollama 服务${NC}"
            echo -e "${YELLOW}请手动启动: ollama serve &${NC}"
            echo -e "${YELLOW}然后重新运行安装脚本${NC}"
            exit 1
        fi
        echo -e "${YELLOW}等待 Ollama 服务响应... (${i}/3)${NC}"
        sleep 2
    fi
done
echo ""

# 2. 拉取模型
echo -e "${YELLOW}[2/4] 检查并拉取模型 ${OLLAMA_MODEL}...${NC}"
if ollama list | grep -q "$OLLAMA_MODEL"; then
    echo -e "${GREEN}✓ 模型 ${OLLAMA_MODEL} 已存在${NC}"
else
    echo -e "${YELLOW}正在拉取模型 ${OLLAMA_MODEL}（这可能需要一些时间）...${NC}"
    ollama pull "$OLLAMA_MODEL"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 模型拉取成功${NC}"
    else
        echo -e "${RED}✗ 模型拉取失败${NC}"
        exit 1
    fi
fi
echo ""

# 3. 安装依赖
echo -e "${YELLOW}[3/4] 检查并安装依赖（jq, curl）...${NC}"

# 检查并安装 jq
if command -v jq &> /dev/null; then
    echo -e "${GREEN}✓ jq 已安装${NC}"
else
    echo -e "${YELLOW}正在安装 jq...${NC}"
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -qq 2>/dev/null || sudo apt-get update
        sudo apt-get install -y jq || error_exit "jq 安装失败，请手动安装: sudo apt-get install -y jq"
    elif command -v yum &> /dev/null; then
        sudo yum install -y jq || error_exit "jq 安装失败，请手动安装: sudo yum install -y jq"
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y jq || error_exit "jq 安装失败，请手动安装: sudo dnf install -y jq"
    else
        error_exit "无法自动安装 jq，请手动安装"
    fi
    echo -e "${GREEN}✓ jq 安装成功${NC}"
fi

# 检查 curl
if command -v curl &> /dev/null; then
    echo -e "${GREEN}✓ curl 已安装${NC}"
else
    echo -e "${RED}✗ curl 未安装，请先安装 curl${NC}"
    exit 1
fi
echo ""

# 4. 创建 cc.sh 脚本
echo -e "${YELLOW}[4/4] 创建 cc.sh 脚本...${NC}"

cat > "$CC_SCRIPT_PATH" << 'CC_SCRIPT_EOF'
#!/bin/bash

# 颜色定义
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Ollama 配置
OLLAMA_URL="http://127.0.0.1:11434/v1"
MODEL="qwen2.5:1.5b"

# 清理命令输出
sanitize() {
    local cmd="$1"
    # 移除代码块标记
    cmd=$(echo "$cmd" | sed 's/```//g' | sed 's/bash//g' | sed 's/shell//g')
    # 移除首尾的代码块标记
    cmd=$(echo "$cmd" | sed 's/^```//' | sed 's/```$//')
    # 只取第一行（命令应该是单行的）
    cmd=$(echo "$cmd" | head -n 1)
    # 移除首尾空白
    cmd=$(echo "$cmd" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    # 移除末尾的反斜杠（可能是换行符导致的）
    cmd=$(echo "$cmd" | sed 's/\\$//')
    echo "$cmd"
}

# 获取命令
get_command() {
    local query="$1"
    # 构建提示词
    local prompt="将中文需求转换为一条可直接执行的 Linux shell 命令。
只输出命令，不要解释、不要 Markdown、不要占位符。
如果缺少参数，使用最常见的默认命令。
注意：代理设置通常指 HTTP/HTTPS 代理（环境变量 http_proxy, https_proxy），不是 DNS 设置。

需求：
${query}

命令：
"

    local system_msg="你是一个 Linux 命令转换助手。只输出命令，不要任何解释。"
    
    # 使用 jq 构建 JSON（快速且可靠）
    local json_data=$(jq -n \
        --arg model "$MODEL" \
        --arg system "$system_msg" \
        --arg prompt "$prompt" \
        '{
            model: $model,
            messages: [
                {role: "system", content: $system},
                {role: "user", content: $prompt}
            ],
            temperature: 0,
            max_tokens: 64
        }')

    # 调用 Ollama API
    local response=$(curl -s -X POST "${OLLAMA_URL}/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ollama" \
        -d "$json_data" 2>&1)

    # 检查 curl 错误
    if [ $? -ne 0 ]; then
        echo "ERROR: curl 请求失败: $response"
        return 1
    fi

    # 使用 jq 提取命令（更可靠）
    local cmd=$(echo "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
    
    # 如果 jq 解析失败，检查是否有错误
    if [ -z "$cmd" ] || [ "$cmd" = "null" ]; then
        local error_msg=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
        if [ -n "$error_msg" ] && [ "$error_msg" != "null" ]; then
            echo "ERROR: $error_msg"
            return 1
        elif echo "$response" | grep -q "error"; then
            echo "ERROR: API 返回错误"
            return 1
        else
            echo "ERROR: empty model output"
            return 1
        fi
    fi

    echo "$cmd"
    return 0
}

# 主函数
main() {
    if [ $# -lt 1 ]; then
        echo "用法: cc <中文需求>"
        exit 1
    fi

    local user_query="$*"
    local cmd=$(get_command "$user_query")

    if [ $? -ne 0 ] || [ "${cmd#ERROR}" != "$cmd" ]; then
        echo -e "${RED}${cmd}${NC}" >&2
        exit 1
    fi

    # 清理命令
    cmd=$(sanitize "$cmd")

    if [ -z "$cmd" ]; then
        echo -e "${RED}错误: 模型返回了空命令${NC}" >&2
        exit 1
    fi

    echo -e "\n${GREEN}> AI 建议:${NC} $cmd"

    echo -ne "${YELLOW}确认执行该命令吗？(y/Enter 执行, n 退出): ${NC}"
    read -r confirm
    if [ -z "$confirm" ] || [ "$confirm" = "y" ] || [ "$confirm" = "yes" ]; then
        echo -e "\n正在执行: $cmd\n"
        eval "$cmd"
    else
        echo "已取消执行。"
    fi
}

main "$@"
CC_SCRIPT_EOF

chmod +x "$CC_SCRIPT_PATH"
echo -e "${GREEN}✓ cc.sh 脚本创建成功${NC}"
echo ""

# 5. 创建 ~/bin 目录并设置 PATH
echo -e "${YELLOW}配置 PATH 和别名...${NC}"
mkdir -p "$BIN_DIR"

# 创建 ~/bin/cc 链接
cat > "$BIN_DIR/cc" << 'BIN_CC_EOF'
#!/bin/bash
exec bash ~/cc.sh "$@"
BIN_CC_EOF
chmod +x "$BIN_DIR/cc"
echo -e "${GREEN}✓ 创建 $BIN_DIR/cc${NC}"

# 更新 .bashrc
BASHRC="$HOME/.bashrc"
if ! grep -q "export PATH=\"\$HOME/bin:\$PATH\"" "$BASHRC" 2>/dev/null; then
    echo "" >> "$BASHRC"
    echo "# cc 命令助手配置" >> "$BASHRC"
    echo 'export PATH="$HOME/bin:$PATH"' >> "$BASHRC"
    echo -e "${GREEN}✓ 已添加 ~/bin 到 PATH${NC}"
fi

# 更新别名（如果存在旧的，先删除）
if grep -q "alias cc=" "$BASHRC" 2>/dev/null; then
    sed -i '/alias cc=/d' "$BASHRC"
fi
echo 'alias cc="bash ~/cc.sh"' >> "$BASHRC"
echo -e "${GREEN}✓ 已设置 cc 别名${NC}"
echo ""

# 完成
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}安装完成！${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}下一步：${NC}"
echo -e "1. 运行以下命令重新加载配置："
echo -e "   ${GREEN}source ~/.bashrc${NC}"
echo ""
echo -e "2. 或者重新打开终端"
echo ""
echo -e "3. 测试命令："
echo -e "   ${GREEN}cc 查看当前目录${NC}"
echo ""
echo -e "${YELLOW}配置信息：${NC}"
echo -e "  - 模型: ${MODEL}"
echo -e "  - 脚本: ${CC_SCRIPT_PATH}"
echo -e "  - 命令: ${BIN_DIR}/cc"
echo ""

