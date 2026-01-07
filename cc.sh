#!/bin/bash

# Ollama 配置
OLLAMA_URL="http://127.0.0.1:11434/v1"
MODEL="qwen2.5:1.5b"

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

# 获取命令
get_command() {
    local query="$1"
    local prompt="将中文需求转换为一条可直接执行的 Linux shell 命令。
只输出命令，不要解释、不要 Markdown、不要占位符。
如果缺少参数，使用最常见的默认命令。

需求：
${query}

命令：
"

    local system_msg="你是一个 Linux 命令转换助手。只输出命令，不要任何解释。"
    
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

    local response=$(curl -s -X POST "${OLLAMA_URL}/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ollama" \
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
        echo -e "\033[0;37mcc v1.0 | $MODEL\033[0m"
        exit 0
    fi
    
    # 预设指令: -u 更新（不依赖模型）
    if [ "$first_arg" = "-u" ] || [ "$first_arg" = "update" ] || [ "$first_arg" = "--update" ]; then
        echo -e "\033[0;37mupdating...\033[0m"
        local update_url="https://raw.githubusercontent.com/jonas-pi/cc-helper/main/cc.sh"
        local script_path="$HOME/cc.sh"
        
        # 备份
        [ -f "$script_path" ] && cp "$script_path" "${script_path}.backup" 2>/dev/null
        
        # 下载
        if curl -fsSL "$update_url" -o "$script_path" 2>/dev/null; then
            chmod +x "$script_path"
            echo -e "\033[0;37mupdated\033[0m"
        else
            echo -e "\033[1;31mfailed\033[0m"
            exit 1
        fi
        exit 0
    fi
    
    # 帮助信息
    if [ $# -lt 1 ] || [ "$first_arg" = "-h" ] || [ "$first_arg" = "--help" ]; then
        echo "用法: cc <中文需求>"
        echo "示例: cc 查看当前目录"
        echo ""
        echo "预设指令："
        echo "  cc hello    - 显示版本信息"
        echo "  cc -u       - 更新脚本"
        exit 1
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

