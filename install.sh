#!/bin/bash

# cc 命令助手安装脚本
# 功能：安装 Ollama、拉取模型、配置 cc 命令

# 确保输出立即刷新（移除可能导致问题的重定向）

# 不要使用 set -e，手动处理错误
# set -e

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

# 显示铭牌
echo -e "\033[1;36m"
echo "  ██████╗ ██████╗     ██╗  ██╗███████╗██╗     ██████╗ ███████╗██████╗ "
echo " ██╔════╝██╔════╝     ██║  ██║██╔════╝██║     ██╔══██╗██╔════╝██╔══██╗"
echo " ██║     ██║    █████╗███████║█████╗  ██║     ██████╔╝█████╗  ██████╔╝"
echo " ██║     ██║    ╚════╝██╔══██║██╔══╝  ██║     ██╔═══╝ ██╔══╝  ██╔══██╗"
echo " ╚██████╗╚██████╗     ██║  ██║███████╗███████╗██║     ███████╗██║  ██║"
echo "  ╚═════╝ ╚═════╝     ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝     ╚══════╝╚═╝  ╚═╝"
echo ""
echo "      AI 命令助手 - 基于 Ollama 的智能命令生成工具"
echo -e "\033[0m"
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  正在安装 cc 命令助手...${NC}"
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
    ollama --version 2>/dev/null || echo "  (版本信息不可用)"
else
    echo -e "${YELLOW}正在安装 Ollama...${NC}"
    if curl -fsSL https://ollama.com/install.sh | sh; then
        echo -e "${GREEN}✓ Ollama 安装成功${NC}"
    else
        error_exit "Ollama 安装失败"
    fi
fi

# 启动 Ollama 服务（如果未运行）
echo -e "${YELLOW}检查 Ollama 服务状态...${NC}"
if ! pgrep -x ollama > /dev/null 2>&1; then
    echo -e "  ${YELLOW}启动 Ollama 服务...${NC}"
    nohup ollama serve > /tmp/ollama.log 2>&1 &
    sleep 3
    # 再次检查是否启动成功
    if ! pgrep -x ollama > /dev/null 2>&1; then
        sleep 2
    fi
    echo -e "  ${GREEN}✓ Ollama 服务已启动${NC}"
else
    echo -e "  ${GREEN}✓ Ollama 服务运行中${NC}"
fi

# 检查 Ollama 是否可访问（最多重试 5 次）
echo -e "${YELLOW}检查 Ollama 连接...${NC}"
OLLAMA_OK=0
for i in {1..5}; do
    if curl -s --max-time 2 "$OLLAMA_URL/api/tags" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓ Ollama 服务运行正常${NC}"
        OLLAMA_OK=1
        break
    else
        if [ $i -lt 5 ]; then
            echo -e "  ${YELLOW}等待服务响应... (${i}/5)${NC}"
            sleep 1
fi
    fi
done

if [ $OLLAMA_OK -eq 0 ]; then
    echo -e "  ${YELLOW}⚠ Ollama 服务未响应，但继续安装...${NC}"
    echo -e "  ${YELLOW}安装完成后请手动启动: ollama serve &${NC}"
fi
echo ""

# 2. 选择并拉取模型
echo -e "${YELLOW}[2/4] 选择 Ollama 模型...${NC}"
echo ""

# 获取系统信息
TOTAL_RAM=$(free -m | awk 'NR==2 {print $2}')
CPU_CORES=$(nproc)
echo -e "${GREEN}系统配置:${NC}"
echo -e "  RAM: ${TOTAL_RAM} MB (~$((TOTAL_RAM / 1024)) GB)"
echo -e "  CPU 核心: ${CPU_CORES}"
echo ""

# 模型列表（模型名称|大小|RAM需求GB|描述）
declare -a MODELS=(
    "qwen2.5:0.5b|500MB|2|最轻量，极快响应，适合低配置"
    "qwen2.5:1.5b|1.5GB|4|轻量快速，推荐日常使用"
    "qwen2.5:3b|3GB|8|平衡性能，准确度高"
    "qwen2.5:7b|7GB|16|高性能，专业级准确度"
    "phi3.5|2.2GB|6|微软模型，英文优秀，中文良好"
    "llama3.2:1b|1GB|3|Meta轻量模型，快速响应"
    "llama3.2:3b|2GB|6|Meta平衡模型，性能出色"
)

# 根据 RAM 给出推荐
echo -e "${GREEN}可用模型:${NC}"
RECOMMENDED=""
RAM_GB=$((TOTAL_RAM / 1024))
for i in "${!MODELS[@]}"; do
    IFS='|' read -r model size ram_need desc <<< "${MODELS[$i]}"
    
    # 判断是否推荐
    if [ "$RAM_GB" -ge "$ram_need" ]; then
        if [ -z "$RECOMMENDED" ]; then
            RECOMMENDED=$((i + 1))
        fi
        echo -e "  $((i + 1)). ${GREEN}${model}${NC} - ${size} - ${desc} (需要 ${ram_need}GB RAM)"
    else
        echo -e "  $((i + 1)). ${model} - ${size} - ${desc} (需要 ${ram_need}GB RAM) ${RED}[配置不足]${NC}"
    fi
done
echo ""

if [ -n "$RECOMMENDED" ]; then
    echo -e "${GREEN}根据您的系统配置 (${RAM_GB}GB RAM)，推荐: 选项 ${RECOMMENDED}${NC}"
else
    echo -e "${YELLOW}警告: 系统 RAM 较低，建议选择最轻量的模型${NC}"
    RECOMMENDED=1
fi
echo ""

echo -e "${YELLOW}请选择要安装的模型（输入序号，多个用空格分隔，或直接回车使用推荐）:${NC}"
read -r selection

# 如果用户直接回车，使用推荐
if [ -z "$selection" ]; then
    selection=$RECOMMENDED
fi

# 解析用户选择
SELECTED_MODELS=()
DEFAULT_MODEL=""
for num in $selection; do
    index=$((num - 1))
    if [ "$index" -ge 0 ] && [ "$index" -lt "${#MODELS[@]}" ]; then
        IFS='|' read -r model size ram_need desc <<< "${MODELS[$index]}"
        SELECTED_MODELS+=("$model")
        if [ -z "$DEFAULT_MODEL" ]; then
            DEFAULT_MODEL="$model"
        fi
    fi
done

if [ "${#SELECTED_MODELS[@]}" -eq 0 ]; then
    echo -e "${RED}错误: 没有选择有效的模型${NC}"
    exit 1
fi

# 如果选择了多个模型，让用户选择默认使用的
if [ "${#SELECTED_MODELS[@]}" -gt 1 ]; then
    echo ""
    echo -e "${YELLOW}您选择了多个模型，请选择默认使用的模型:${NC}"
    for i in "${!SELECTED_MODELS[@]}"; do
        echo -e "  $((i + 1)). ${SELECTED_MODELS[$i]}"
    done
    read -r default_choice
    default_index=$((default_choice - 1))
    if [ "$default_index" -ge 0 ] && [ "$default_index" -lt "${#SELECTED_MODELS[@]}" ]; then
        DEFAULT_MODEL="${SELECTED_MODELS[$default_index]}"
    fi
fi

OLLAMA_MODEL="$DEFAULT_MODEL"
echo ""
echo -e "${GREEN}将安装以下模型: ${SELECTED_MODELS[*]}${NC}"
echo -e "${GREEN}默认使用: ${OLLAMA_MODEL}${NC}"
echo ""

# 拉取选中的模型
for model in "${SELECTED_MODELS[@]}"; do
    if ollama list 2>/dev/null | grep -q "$model"; then
        echo -e "${GREEN}✓ ${model} 已存在${NC}"
    else
        echo -e "${YELLOW}正在拉取模型 ${model}...${NC}"
        if ollama pull "$model" 2>&1; then
            echo -e "${GREEN}✓ ${model} 拉取完成${NC}"
        else
            echo -e "${RED}✗ ${model} 拉取失败${NC}"
        fi
    fi
done
echo ""

# 3. 安装依赖
echo -e "${YELLOW}[3/4] 检查并安装依赖（jq, curl）...${NC}"

# 检查并安装 jq
if command -v jq &> /dev/null; then
    echo -e "  ${GREEN}✓ jq 已安装${NC}"
else
    echo -e "${YELLOW}正在安装 jq...${NC}"
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -qq 2>/dev/null || sudo apt-get update > /dev/null 2>&1
        sudo apt-get install -y jq > /dev/null 2>&1 || error_exit "jq 安装失败，请手动安装: sudo apt-get install -y jq"
    elif command -v yum &> /dev/null; then
        sudo yum install -y jq > /dev/null 2>&1 || error_exit "jq 安装失败，请手动安装: sudo yum install -y jq"
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y jq > /dev/null 2>&1 || error_exit "jq 安装失败，请手动安装: sudo dnf install -y jq"
    else
        error_exit "无法自动安装 jq，请手动安装"
    fi
    echo -e "  ${GREEN}✓ jq 安装成功${NC}"
fi

# 检查 curl
if command -v curl &> /dev/null; then
    echo -e "  ${GREEN}✓ curl 已安装${NC}"
else
    echo -e "  ${RED}✗ curl 未安装，请先安装 curl${NC}"
    exit 1
fi
echo ""

# 4. 下载 cc.sh 脚本
echo -e "${YELLOW}[4/4] 下载 cc.sh 脚本...${NC}"

# 从 GitHub 下载最新的 cc.sh
if curl -fsSL "https://raw.githubusercontent.com/jonas-pi/cc-helper/main/cc.sh" -o "$CC_SCRIPT_PATH" 2>/dev/null; then
    chmod +x "$CC_SCRIPT_PATH"
    echo -e "  ${GREEN}✓ cc.sh 脚本下载成功${NC}"
    echo ""
else
    # 如果下载失败，创建基本版本
    echo -e "  ${YELLOW}下载失败，创建基本版本...${NC}"
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
        echo "示例: cc 查看当前目录"
        echo ""
        echo "预设指令："
        echo "  cc hello    - 显示欢迎信息，测试安装"
        echo "  cc -u       - 更新脚本到最新版本"
        exit 1
    fi

    # 处理预设指令
    local first_arg="$1"
    
    # 预设指令 1: hello - 显示欢迎信息
    if [ "$first_arg" = "hello" ]; then
        echo -e "\033[0;37mcc v1.0 | $MODEL\033[0m"
        exit 0
    fi
    
    # 预设指令 2: -u/update - 更新脚本
    if [ "$first_arg" = "-u" ] || [ "$first_arg" = "update" ] || [ "$first_arg" = "--update" ]; then
        local update_url="https://raw.githubusercontent.com/jonas-pi/cc-helper/main/install.sh"
        local script_path="$HOME/cc.sh"
        
        # 备份
        if [ -f "$script_path" ]; then
            cp "$script_path" "${script_path}.backup" 2>/dev/null
        fi
        
        # 下载
        if curl -fsSL "$update_url" | bash -s -- --update-only 2>/dev/null; then
            echo -e "\033[0;37mupdated\033[0m"
        else
            echo -e "\033[1;31mfailed\033[0m"
            exit 1
        fi
        exit 0
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

    echo -e "\033[0;37m> $cmd\033[0m"

    echo -ne "[y/n] "
    read -r confirm
    if [ -z "$confirm" ] || [ "$confirm" = "y" ] || [ "$confirm" = "yes" ]; then
        eval "$cmd"
    fi
}

main "$@"
CC_SCRIPT_EOF

chmod +x "$CC_SCRIPT_PATH"
echo -e "  ${GREEN}✓ cc.sh 脚本创建成功${NC}"
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
echo -e "  ${GREEN}✓ 创建 $BIN_DIR/cc${NC}"

# 更新 .bashrc
BASHRC="$HOME/.bashrc"
if ! grep -q "export PATH=\"\$HOME/bin:\$PATH\"" "$BASHRC" 2>/dev/null; then
    echo "" >> "$BASHRC"
    echo "# cc 命令助手配置" >> "$BASHRC"
    echo 'export PATH="$HOME/bin:$PATH"' >> "$BASHRC"
    echo -e "  ${GREEN}✓ 已添加 ~/bin 到 PATH${NC}"
fi

# 更新别名（如果存在旧的，先删除）
if grep -q "alias cc=" "$BASHRC" 2>/dev/null; then
    sed -i '/alias cc=/d' "$BASHRC"
fi
echo 'alias cc="bash ~/cc.sh"' >> "$BASHRC"
echo -e "  ${GREEN}✓ 已设置 cc 别名${NC}"
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

