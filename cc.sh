#!/bin/bash

# Ollama 配置
OLLAMA_URL="http://127.0.0.1:11434/v1"
MODEL="qwen2.5:1.5b"

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
    if [ $# -lt 1 ]; then
        echo "用法: cc <中文需求>"
        echo "示例: cc 查看当前目录"
        echo ""
        echo "预设指令："
        echo "  cc hello    - 显示版本信息"
        echo "  cc -u       - 更新脚本"
        exit 1
    fi

    local first_arg="$1"
    
    # 预设指令: hello
    if [ "$first_arg" = "hello" ]; then
        echo -e "\033[0;37mcc v1.0 | $MODEL\033[0m"
        exit 0
    fi
    
    # 预设指令: -u 更新
    if [ "$first_arg" = "-u" ] || [ "$first_arg" = "update" ] || [ "$first_arg" = "--update" ]; then
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

