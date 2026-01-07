#!/bin/bash

# 版本信息
VERSION="1.7.0"

# 配置文件路径
CONFIG_FILE="$HOME/.cc_config"

# 默认配置
OLLAMA_URL="http://127.0.0.1:11434/v1"
MODEL="qwen2.5:1.5b"
MODE="work"  # work: 工作模式（只输出命令）, rest: 休息模式（可以聊天）
API_TYPE="ollama"  # ollama, openai, anthropic, custom
API_KEY=""  # API 密钥（如果需要）

# 加载配置文件
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# 检测终端编码并选择合适的字符
LANG_ENCODING=$(echo $LANG | grep -i "utf")
if [ -n "$LANG_ENCODING" ]; then
    # UTF-8 编码：使用可爱的 Unicode 字符
    EMOJI_HELLO="(｡･ω･｡)"
    BULLET="•"
    BULLET_CURRENT="•"
    BOX_TOP="╔════════════════════════════════════════════╗"
    BOX_MID="║         CC 命令助手 - 使用指南          ║"
    BOX_BOT="╚════════════════════════════════════════════╝"
else
    # 其他编码：使用 ASCII 兼容字符
    EMOJI_HELLO="^_^"
    BULLET="-"
    BULLET_CURRENT="*"
    BOX_TOP="============================================"
    BOX_MID="         CC 命令助手 - 使用指南          "
    BOX_BOT="============================================"
fi

# 检查并自动选择可用模型
check_and_select_model() {
    # 检查当前配置的模型是否存在
    if ollama list 2>/dev/null | grep -q "^${MODEL}"; then
        return 0
    fi
    
    # 如果配置的模型不存在，尝试从已安装的模型中选择
    local available_models=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}')
    
    if [ -z "$available_models" ]; then
        echo -e "\033[1;31mERROR: 未找到已安装的模型\033[0m" >&2
        echo -e "\033[0;37m请运行: ollama pull qwen2.5:1.5b\033[0m" >&2
        return 1
    fi
    
    # 优先级列表（Linux优先推荐中文模型）
    local priority_models=("qwen2.5:1.5b" "qwen2.5:3b" "qwen2.5:0.5b" "qwen2.5:7b" "phi3.5" "llama3.2:3b" "llama3.2:1b")
    
    # 从优先级列表中找到第一个已安装的模型
    for preferred in "${priority_models[@]}"; do
        if echo "$available_models" | grep -q "^${preferred}$"; then
            MODEL="$preferred"
            echo -e "\033[0;33m注意: 使用模型 ${MODEL}\033[0m" >&2
            return 0
        fi
    done
    
    # 如果优先级列表中都没有，使用第一个可用的模型
    MODEL=$(echo "$available_models" | head -n 1)
    echo -e "\033[0;33m注意: 使用模型 ${MODEL}\033[0m" >&2
    return 0
}

# 清理命令输出
sanitize() {
    local cmd="$1"
    cmd=$(echo "$cmd" | sed 's/```//g' | sed 's/bash//g' | sed 's/shell//g')
    cmd=$(echo "$cmd" | sed 's/^```//' | sed 's/```$//')
    cmd=$(echo "$cmd" | head -n 1)
    cmd=$(echo "$cmd" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    cmd=$(echo "$cmd" | sed 's/\\$//')
    echo "$cmd"
}

# 获取命令或回复
get_command() {
    local query="$1"
    
    # 根据模式设置不同的提示词
    local prompt=""
    local system_msg=""
    
    if [ "$MODE" = "rest" ]; then
        # 休息模式：可以聊天
        prompt="请用友好、轻松的语气回复用户。可以聊天、解答问题、提供建议。

用户说：
${query}

回复：
"
        system_msg="你是 cc，一个友好的 AI 命令助手。你目前处于休息模式，可以和用户聊天交流。你的主要工作是帮助用户生成命令（工作模式），但现在是休息时间，可以轻松聊天。"
    else
        # 工作模式：只输出命令
        prompt="将中文需求转换为一条可直接执行的 Linux shell 命令。
只输出命令，不要解释、不要 Markdown、不要占位符。
如果缺少参数，使用最常见的默认命令。

需求：
${query}

命令：
"
        system_msg="你是 cc，一个 Linux 命令转换助手。只输出命令，不要任何解释。"
    fi
    
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

    # 构建 header
    local auth_header=""
    if [ -n "$API_KEY" ]; then
        auth_header="-H \"Authorization: Bearer $API_KEY\""
    elif [ "$API_TYPE" = "ollama" ]; then
        auth_header="-H \"Authorization: Bearer ollama\""
    fi
    
    local response=$(curl -s -X POST "${OLLAMA_URL}/chat/completions" \
        -H "Content-Type: application/json" \
        $auth_header \
        -d "$json_data" 2>&1)

    if [ $? -ne 0 ]; then
        echo "ERROR: curl 请求失败"
        return 1
    fi

    local cmd=$(echo "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
    
    if [ -z "$cmd" ] || [ "$cmd" = "null" ]; then
        echo "ERROR: 模型无响应"
        return 1
    fi
    
    echo "$cmd"
    return 0
}

# 主函数
main() {
    local first_arg="$1"
    
    # 预设指令: hello（不依赖模型）
    if [ "$first_arg" = "hello" ]; then
        echo -e "\033[0;37m$EMOJI_HELLO cc v$VERSION\033[0m"
        echo ""
        
        # 显示当前模型
        echo -e "\033[0;37m当前模型: \033[1;32m$MODEL\033[0m"
        
        # 显示当前模式
        if [ "$MODE" = "rest" ]; then
            echo -e "\033[0;37m当前模式: \033[1;35m休息模式\033[0m \033[0;37m(可以聊天)\033[0m"
        else
            echo -e "\033[0;37m当前模式: \033[1;36m工作模式\033[0m \033[0;37m(命令助手)\033[0m"
        fi
        
        # 列出所有已安装的模型
        local models=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}')
        if [ -n "$models" ]; then
            echo ""
            echo -e "\033[0;37m已安装的模型:\033[0m"
            while IFS= read -r model; do
                if [ "$model" = "$MODEL" ]; then
                    echo -e "  $BULLET_CURRENT \033[1;32m$model\033[0m"
                else
                    echo -e "  $BULLET $model"
                fi
            done <<< "$models"
        fi
        
        echo ""
        echo -e "\033[0;37m准备好了~ 有什么可以帮你的吗？\033[0m"
        exit 0
    fi
    
    # 预设指令: -w 工作模式
    if [ "$first_arg" = "-w" ] || [ "$first_arg" = "work" ]; then
        sed -i 's/^MODE=.*/MODE="work"/' "$HOME/cc.sh"
        echo -e "\033[1;36m已切换到工作模式\033[0m \033[0;37m- 专注命令，高效执行\033[0m"
        exit 0
    fi
    
    # 预设指令: -r 休息模式
    if [ "$first_arg" = "-r" ] || [ "$first_arg" = "rest" ] || [ "$first_arg" = "chat" ]; then
        sed -i 's/^MODE=.*/MODE="rest"/' "$HOME/cc.sh"
        echo -e "\033[1;35m已切换到休息模式\033[0m \033[0;37m- 放松一下，聊聊天吧~\033[0m"
        exit 0
    fi
    
    # 预设指令: -u 更新（不依赖模型）
    if [ "$first_arg" = "-u" ] || [ "$first_arg" = "update" ] || [ "$first_arg" = "--update" ]; then
        echo -e "\033[1;36m正在检查更新...\033[0m"
        
        # 获取远程版本号
        local remote_version=$(curl -fsSL "https://raw.githubusercontent.com/jonas-pi/cc-helper/main/VERSION" 2>/dev/null)
        
        if [ -z "$remote_version" ]; then
            echo -e "\033[1;31m无法获取版本信息\033[0m"
            echo -e "\033[0;37m是否继续更新? [y/n]\033[0m"
            read -r confirm < /dev/tty
            if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                exit 0
            fi
        else
            echo -e "\033[0;37m当前版本: \033[1;33m$VERSION\033[0m"
            echo -e "\033[0;37m最新版本: \033[1;32m$remote_version\033[0m"
            echo ""
            
            # 版本比较
            if [ "$VERSION" = "$remote_version" ]; then
                echo -e "\033[1;32m✓ 已是最新版本\033[0m"
                exit 0
            fi
            
            # 获取更新日志
            echo -e "\033[1;35m更新内容:\033[0m"
            local changelog=$(curl -fsSL "https://raw.githubusercontent.com/jonas-pi/cc-helper/main/CHANGELOG.md" 2>/dev/null | head -30)
            if [ -n "$changelog" ]; then
                echo "$changelog" | grep -A 20 "## v$remote_version" | head -20
            fi
            echo ""
            
            echo -e "\033[0;33m是否更新到 v$remote_version? [y/n]\033[0m"
            read -r confirm < /dev/tty
            if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                echo -e "\033[0;37m已取消更新\033[0m"
                exit 0
            fi
        fi
        
        echo -e "\033[0;37m正在下载最新版本...\033[0m"
        local update_url="https://raw.githubusercontent.com/jonas-pi/cc-helper/main/cc.sh"
        local script_path="$HOME/cc.sh"
        
        # 备份
        [ -f "$script_path" ] && cp "$script_path" "${script_path}.backup" 2>/dev/null
        
        # 下载
        if curl -fsSL "$update_url" -o "$script_path" 2>/dev/null; then
            chmod +x "$script_path"
            echo -e "\033[1;32m✓ 更新完成！\033[0m"
            echo -e "\033[0;37m现在运行: \033[1;32mcc hello\033[0m"
        else
            echo -e "\033[1;31m✗ 更新失败\033[0m"
            exit 1
        fi
        exit 0
    fi
    
    # 预设指令: -change 切换模型
    if [ "$first_arg" = "-change" ] || [ "$first_arg" = "change" ]; then
        local models=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}')
        
        if [ -z "$models" ]; then
            echo -e "\033[1;31mERROR: 未找到已安装的模型\033[0m"
            exit 1
        fi
        
        echo -e "\033[0;37m已安装的模型:\033[0m"
        local i=1
        while IFS= read -r model; do
            if [ "$model" = "$MODEL" ]; then
                echo -e "  $i. \033[1;32m$model\033[0m (当前)"
            else
                echo -e "  $i. $model"
            fi
            i=$((i + 1))
        done <<< "$models"
        
        echo ""
        echo -ne "\033[0;33m请选择模型 (序号): \033[0m"
        read -r choice < /dev/tty
        
        local selected=$(echo "$models" | sed -n "${choice}p")
        if [ -z "$selected" ]; then
            echo -e "\033[1;31m无效选择\033[0m"
            exit 1
        fi
        
        # 更新脚本中的 MODEL 变量
        sed -i "s/^MODEL=.*/MODEL=\"$selected\"/" "$HOME/cc.sh"
        echo -e "\033[0;37m已切换到: $selected\033[0m"
        exit 0
    fi
    
    # 预设指令: -add 安装新模型
    if [ "$first_arg" = "-add" ] || [ "$first_arg" = "add" ]; then
        echo -e "\033[0;37m推荐模型:\033[0m"
        echo "  1. qwen2.5:0.5b  - 超轻量 (400MB)"
        echo "  2. qwen2.5:1.5b  - 轻量推荐 (1GB)"
        echo "  3. qwen2.5:3b    - 平衡之选 (2GB)"
        echo "  4. qwen2.5:7b    - 高性能 (4.7GB)"
        echo "  5. phi3.5        - 微软模型 (2.2GB)"
        echo "  6. llama3.2:1b   - Meta轻量 (1.2GB)"
        echo "  7. llama3.2:3b   - Meta平衡 (2GB)"
        echo "  8. 自定义模型名"
        echo ""
        echo -ne "\033[0;33m请选择 (序号或输入模型名): \033[0m"
        read -r choice < /dev/tty
        
        case "$choice" in
            1) local model="qwen2.5:0.5b" ;;
            2) local model="qwen2.5:1.5b" ;;
            3) local model="qwen2.5:3b" ;;
            4) local model="qwen2.5:7b" ;;
            5) local model="phi3.5" ;;
            6) local model="llama3.2:1b" ;;
            7) local model="llama3.2:3b" ;;
            8) echo -ne "\033[0;33m输入模型名: \033[0m"
               read -r model < /dev/tty ;;
            *) local model="$choice" ;;
        esac
        
        if [ -z "$model" ]; then
            echo -e "\033[1;31m无效输入\033[0m"
            exit 1
        fi
        
        echo -e "\033[0;37m正在安装 $model...\033[0m"
        if ollama pull "$model"; then
            echo -e "\033[0;37m安装完成\033[0m"
            echo -ne "\033[0;33m是否切换到此模型? [y/n] \033[0m"
            read -r switch < /dev/tty
            if [ "$switch" = "y" ] || [ "$switch" = "Y" ] || [ -z "$switch" ]; then
                sed -i "s/^MODEL=.*/MODEL=\"$model\"/" "$HOME/cc.sh"
                echo -e "\033[0;37m已切换到: $model\033[0m"
            fi
        else
            echo -e "\033[1;31m安装失败\033[0m"
            exit 1
        fi
        exit 0
    fi
    
    # 预设指令: -config 配置 API
    if [ "$first_arg" = "-config" ] || [ "$first_arg" = "config" ]; then
        echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo -e "\033[1;36m          CC API 配置 - 成长空间          \033[0m"
        echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo ""
        echo -e "\033[0;37m当前配置:\033[0m"
        echo -e "  API 类型: \033[1;32m$API_TYPE\033[0m"
        echo -e "  API 地址: \033[0;37m$OLLAMA_URL\033[0m"
        echo -e "  模型: \033[0;37m$MODEL\033[0m"
        [ -n "$API_KEY" ] && echo -e "  API Key: \033[0;37m${API_KEY:0:10}...\033[0m" || echo -e "  API Key: \033[0;33m(未设置)\033[0m"
        echo ""
        echo -e "\033[1;35m可选 API 类型:\033[0m"
        echo -e "  1. \033[1;32mollama\033[0m       - 本地 Ollama（默认，免费）"
        echo -e "  2. \033[1;33mopenai\033[0m       - OpenAI GPT 系列"
        echo -e "  3. \033[1;35manthropic\033[0m    - Anthropic Claude 系列"
        echo -e "  4. \033[1;34mdeepseek\033[0m     - DeepSeek（国内，高性价比）"
        echo -e "  5. \033[1;36mdoubao\033[0m       - 豆包/火山方舟（字节跳动）"
        echo -e "  6. \033[1;32mqwen\033[0m         - 通义千问/阿里云百炼"
        echo -e "  7. \033[1;36mcustom\033[0m       - 自定义兼容 OpenAI API 的服务"
        echo ""
        echo -ne "\033[0;33m选择 API 类型 (1-7，直接回车保持当前): \033[0m"
        read -r api_choice < /dev/tty
        
        case "$api_choice" in
            1)
                API_TYPE="ollama"
                echo -ne "\033[0;33mOllama 地址 [http://127.0.0.1:11434/v1]: \033[0m"
                read -r url < /dev/tty
                OLLAMA_URL="${url:-http://127.0.0.1:11434/v1}"
                API_KEY=""
                echo -ne "\033[0;33m模型名称 [qwen2.5:1.5b]: \033[0m"
                read -r model < /dev/tty
                MODEL="${model:-qwen2.5:1.5b}"
                ;;
            2)
                API_TYPE="openai"
                OLLAMA_URL="https://api.openai.com/v1"
                echo -ne "\033[0;33mOpenAI API Key: \033[0m"
                read -r key < /dev/tty
                API_KEY="$key"
                echo -ne "\033[0;33m模型名称 [gpt-3.5-turbo]: \033[0m"
                read -r model < /dev/tty
                MODEL="${model:-gpt-3.5-turbo}"
                ;;
            3)
                API_TYPE="anthropic"
                OLLAMA_URL="https://api.anthropic.com/v1"
                echo -ne "\033[0;33mAnthropic API Key: \033[0m"
                read -r key < /dev/tty
                API_KEY="$key"
                echo -ne "\033[0;33m模型名称 [claude-3-haiku-20240307]: \033[0m"
                read -r model < /dev/tty
                MODEL="${model:-claude-3-haiku-20240307}"
                ;;
            4)
                API_TYPE="deepseek"
                OLLAMA_URL="https://api.deepseek.com"
                echo -ne "\033[0;33mDeepSeek API Key: \033[0m"
                read -r key < /dev/tty
                API_KEY="$key"
                echo -ne "\033[0;33m模型名称 [deepseek-chat]: \033[0m"
                read -r model < /dev/tty
                MODEL="${model:-deepseek-chat}"
                ;;
            5)
                API_TYPE="doubao"
                echo -ne "\033[0;33m火山方舟 API 地址 [https://ark.cn-beijing.volces.com/api/v3]: \033[0m"
                read -r url < /dev/tty
                OLLAMA_URL="${url:-https://ark.cn-beijing.volces.com/api/v3}"
                echo -ne "\033[0;33m火山方舟 API Key: \033[0m"
                read -r key < /dev/tty
                API_KEY="$key"
                echo -ne "\033[0;33m模型名称 (如 doubao-pro-32k): \033[0m"
                read -r model < /dev/tty
                MODEL="$model"
                ;;
            6)
                API_TYPE="qwen"
                OLLAMA_URL="https://dashscope.aliyuncs.com/compatible-mode/v1"
                echo -ne "\033[0;33m阿里云百炼 API Key: \033[0m"
                read -r key < /dev/tty
                API_KEY="$key"
                echo -ne "\033[0;33m模型名称 [qwen-plus]: \033[0m"
                read -r model < /dev/tty
                MODEL="${model:-qwen-plus}"
                ;;
            7)
                API_TYPE="custom"
                echo -ne "\033[0;33mAPI 地址: \033[0m"
                read -r url < /dev/tty
                OLLAMA_URL="$url"
                echo -ne "\033[0;33mAPI Key (可选，直接回车跳过): \033[0m"
                read -r key < /dev/tty
                API_KEY="$key"
                echo -ne "\033[0;33m模型名称: \033[0m"
                read -r model < /dev/tty
                MODEL="$model"
                ;;
            "")
                echo -e "\033[0;37m保持当前配置\033[0m"
                exit 0
                ;;
            *)
                echo -e "\033[1;31m无效选择\033[0m"
                exit 1
                ;;
        esac
        
        # 保存配置
        cat > "$CONFIG_FILE" << EOF
# CC 配置文件
# 由 cc -config 自动生成

API_TYPE="$API_TYPE"
OLLAMA_URL="$OLLAMA_URL"
MODEL="$MODEL"
API_KEY="$API_KEY"
MODE="$MODE"
EOF
        
        echo ""
        echo -e "\033[1;32m✓ 配置已保存到 $CONFIG_FILE\033[0m"
        echo -e "\033[0;37m现在运行: \033[1;32mcc hello\033[0m"
        exit 0
    fi
    
    # 预设指令: -del 删除模型
    if [ "$first_arg" = "-del" ] || [ "$first_arg" = "delete" ] || [ "$first_arg" = "rm" ]; then
        local models=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}')
        
        if [ -z "$models" ]; then
            echo -e "\033[1;31mERROR: 未找到已安装的模型\033[0m"
            exit 1
        fi
        
        echo -e "\033[0;37m已安装的模型:\033[0m"
        local i=1
        while IFS= read -r model; do
            if [ "$model" = "$MODEL" ]; then
                echo -e "  $i. \033[1;32m$model\033[0m (当前使用)"
            else
                echo -e "  $i. $model"
            fi
            i=$((i + 1))
        done <<< "$models"
        
        echo ""
        echo -ne "\033[0;33m请选择要删除的模型 (序号，多个用空格分隔): \033[0m"
        read -r choices < /dev/tty
        
        for choice in $choices; do
            local selected=$(echo "$models" | sed -n "${choice}p")
            if [ -z "$selected" ]; then
                echo -e "\033[1;31m无效序号: $choice\033[0m"
                continue
            fi
            
            if [ "$selected" = "$MODEL" ]; then
                echo -e "\033[1;33m警告: $selected 是当前使用的模型\033[0m"
                echo -ne "\033[0;33m确认删除? [y/n] \033[0m"
                read -r confirm < /dev/tty
                if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                    echo -e "\033[0;37m跳过 $selected\033[0m"
                    continue
                fi
            fi
            
            echo -e "\033[0;37m正在删除 $selected...\033[0m"
            if ollama rm "$selected" 2>/dev/null; then
                echo -e "\033[0;37m已删除 $selected\033[0m"
            else
                echo -e "\033[1;31m删除失败: $selected\033[0m"
            fi
        done
        exit 0
    fi
    
    # 帮助信息
    if [ $# -lt 1 ] || [ "$first_arg" = "-h" ] || [ "$first_arg" = "--help" ] || [ "$first_arg" = "-help" ] || [ "$first_arg" = "help" ]; then
        echo -e "\033[1;36m$BOX_TOP\033[0m"
        echo -e "\033[1;36m$BOX_MID\033[0m"
        echo -e "\033[1;36m$BOX_BOT\033[0m"
        echo ""
        echo -e "\033[1;33m基本用法:\033[0m"
        echo -e "  \033[0;37mcc <中文需求>\033[0m"
        echo -e "  示例: \033[0;32mcc 查看当前目录\033[0m"
        echo ""
        echo -e "\033[1;33m预设指令:\033[0m"
        echo ""
        echo -e "  \033[1;35m信息查询\033[0m"
        echo -e "    \033[0;32mcc hello\033[0m        显示版本、模型和系统信息"
        echo -e "    \033[0;32mcc -h, --help\033[0m   显示此帮助信息"
        echo ""
        echo -e "  \033[1;35m模式切换\033[0m"
        echo -e "    \033[0;32mcc -w\033[0m           工作模式（命令助手，只输出命令）"
        echo -e "    \033[0;32mcc -r\033[0m           休息模式（聊天模式，可以对话）"
        echo ""
        echo -e "  \033[1;35m模型管理\033[0m"
        echo -e "    \033[0;32mcc -change\033[0m      切换使用的模型"
        echo -e "    \033[0;32mcc -add\033[0m         安装新模型"
        echo -e "    \033[0;32mcc -del\033[0m         删除已安装的模型"
        echo ""
        echo -e "  \033[1;35m更新维护\033[0m"
        echo -e "    \033[0;32mcc -u\033[0m           更新 cc 脚本到最新版本"
        echo ""
        echo -e "\033[1;33m使用示例:\033[0m"
        echo -e "  工作模式: \033[0;32mcc 查看磁盘使用情况\033[0m"
        echo -e "  休息模式: \033[0;32mcc 今天天气怎么样？\033[0m"
        echo ""
        echo -e "\033[0;37m提示: 运行 \033[1;32mcc hello\033[0;37m 查看当前配置\033[0m"
        exit 0
    fi

    # 检查并选择可用模型
    if ! check_and_select_model; then
        exit 1
    fi
    
    local user_query="$*"
    local cmd=$(get_command "$user_query")

    if [ $? -ne 0 ] || [ "${cmd#ERROR}" != "$cmd" ]; then
        echo -e "\033[1;31m${cmd}\033[0m" >&2
        exit 1
    fi

    # 休息模式：直接输出回复
    if [ "$MODE" = "rest" ]; then
        echo -e "\033[0;37m$cmd\033[0m"
        exit 0
    fi
    
    # 工作模式：清理命令并执行
    cmd=$(sanitize "$cmd")

    if [ -z "$cmd" ]; then
        echo -e "\033[1;31mERROR: 空命令\033[0m" >&2
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

