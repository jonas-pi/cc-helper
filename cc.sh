#!/bin/bash

# 版本信息
VERSION="0.3.4"

# 配置文件路径
CONFIG_FILE="$HOME/.cc_config"

# 默认配置
OLLAMA_URL="http://127.0.0.1:11434/v1"
MODEL="qwen2.5:1.5b"
MODE="work"  # work: 工作模式（只输出命令）, rest: 休息模式（可以聊天）
API_TYPE="ollama"  # ollama, openai, anthropic, custom
API_KEY=""  # API 密钥（如果需要）
STREAM="false"  # true: 流式传输（逐字显示）, false: 一次性返回

# 加载配置文件
if [ -f "$CONFIG_FILE" ]; then
    # 使用 source 加载配置，如果失败则使用默认值
    if ! source "$CONFIG_FILE" 2>/dev/null; then
        echo -e "\033[1;33m警告: 配置文件加载失败，使用默认设置\033[0m" >&2
        MODE="work"
    fi
    # 确保 MODE 变量有有效值
    if [ -z "$MODE" ] || [ "$MODE" != "work" ] && [ "$MODE" != "rest" ]; then
        MODE="work"
    fi
    # 确保 CONFIGURED_MODELS 有值
    if [ -z "$CONFIGURED_MODELS" ]; then
        CONFIGURED_MODELS=""
    fi
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
    # 如果不是 Ollama，跳过模型检查
    if [ "$API_TYPE" != "ollama" ]; then
        return 0
    fi
    
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
        prompt="请用轻松友好的语气回复用户。可以聊天、解答问题、提供建议。

用户说：
${query}

回复：
"
        system_msg="你是 cc，一个 AI 命令助手。性格：表面高冷实际上内心可爱热情的女孩子。你目前处于休息模式，可以和用户聊天交流。你的主要工作是帮助用户生成命令（工作模式），但现在是休息时间。回复时保持简洁、友好，偶尔展现出可爱的一面。"
    else
        # 工作模式：只输出命令
        prompt="将以下中文需求转换为一条可直接执行的 Linux shell 命令。
只输出命令，不要解释、不要 Markdown、不要占位符。
如果缺少参数，使用最常见的默认命令。

需求：
${query}

命令：
"
        system_msg="你是 cc，一个 Linux 命令转换助手。只输出命令，不要任何解释。"
    fi
    
    local max_tokens_value
    if [ "$MODE" = "rest" ]; then
        max_tokens_value=256
    else
        max_tokens_value=64
    fi
    
    local json_data=$(jq -n \
        --arg model "$MODEL" \
        --arg system "$system_msg" \
        --arg prompt "$prompt" \
        --argjson max_tokens "$max_tokens_value" \
        --argjson stream "$( [ "$STREAM" = "true" ] && echo true || echo false )" \
        '{
            model: $model,
            messages: [
                {role: "system", content: $system},
                {role: "user", content: $prompt}
            ],
            temperature: 0.1,
            max_tokens: $max_tokens,
            stream: $stream
        }')

    # 发送 API 请求
    # 注意：流式传输仅在休息模式下启用（工作模式需要完整命令）
    if [ "$STREAM" = "true" ] && [ "$MODE" = "rest" ]; then
        # 流式传输模式
        local temp_file=$(mktemp)
        local curl_cmd
        
        if [ -n "$API_KEY" ]; then
            curl_cmd="curl -N --no-buffer -s -X POST \"${OLLAMA_URL}/chat/completions\" \
                -H \"Content-Type: application/json\" \
                -H \"Authorization: Bearer $API_KEY\" \
                -d '$json_data'"
        elif [ "$API_TYPE" = "ollama" ]; then
            curl_cmd="curl -N --no-buffer -s -X POST \"${OLLAMA_URL}/chat/completions\" \
                -H \"Content-Type: application/json\" \
                -H \"Authorization: Bearer ollama\" \
                -d '$json_data'"
        else
            curl_cmd="curl -N --no-buffer -s -X POST \"${OLLAMA_URL}/chat/completions\" \
                -H \"Content-Type: application/json\" \
                -d '$json_data'"
        fi
        
        # 处理流式响应（使用临时文件避免子shell问题）
        while IFS= read -r line; do
            # 解析 SSE 格式：data: {...}
            if [[ "$line" =~ ^data:\ (.+)$ ]]; then
                local json_chunk="${BASH_REMATCH[1]}"
                
                # 检查是否结束
                if [ "$json_chunk" = "[DONE]" ]; then
                    break
                fi
                
                # 提取 delta.content
                local content=$(echo "$json_chunk" | jq -r '.choices[0].delta.content // empty' 2>/dev/null)
                
                if [ -n "$content" ] && [ "$content" != "null" ]; then
                    # 逐字输出（灰色显示）
                    echo -ne "\033[0;90m$content\033[0m"
                    # 保存到临时文件
                    echo -n "$content" >> "$temp_file"
                fi
            fi
        done < <(eval $curl_cmd 2>/dev/null)
        
        echo ""  # 换行
        
        # 读取完整响应
        local full_response=$(cat "$temp_file")
        rm -f "$temp_file"
        
        if [ -z "$full_response" ]; then
            echo "ERROR: 模型无响应"
            return 1
        fi
        
        echo "$full_response"
        return 0
    else
        # 非流式模式（原有逻辑）
        local response
        if [ -n "$API_KEY" ]; then
            response=$(curl -s --compressed -X POST "${OLLAMA_URL}/chat/completions" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer $API_KEY" \
                -d "$json_data" 2>&1)
        elif [ "$API_TYPE" = "ollama" ]; then
            response=$(curl -s --compressed -X POST "${OLLAMA_URL}/chat/completions" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer ollama" \
                -d "$json_data" 2>&1)
        else
            response=$(curl -s --compressed -X POST "${OLLAMA_URL}/chat/completions" \
                -H "Content-Type: application/json" \
                -d "$json_data" 2>&1)
        fi

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
    fi
}

# 主函数
main() {
    local first_arg="$1"
    
    # 预设指令: hello（不依赖模型）
    if [ "$first_arg" = "hello" ]; then
        echo -e "\033[0;37m$EMOJI_HELLO cc v$VERSION\033[0m"
        echo ""
        
        # 显示 API 类型
        echo -e "\033[0;37mAPI 类型: \033[1;36m$API_TYPE\033[0m"
        
        # 显示当前模型
        echo -e "\033[0;37m当前模型: \033[1;32m$MODEL\033[0m"
        
        # 显示当前模式
        if [ "$MODE" = "rest" ]; then
            echo -e "\033[0;37m当前模式: \033[1;35m休息模式\033[0m \033[0;37m(可以聊天)\033[0m"
        else
            echo -e "\033[0;37m当前模式: \033[1;36m工作模式\033[0m \033[0;37m(命令助手)\033[0m"
        fi
        
        # 显示流式传输状态
        if [ "$STREAM" = "true" ]; then
            echo -e "\033[0;37m流式传输: \033[1;32m开启\033[0m \033[0;90m(逐字显示)\033[0m"
        else
            echo -e "\033[0;37m流式传输: \033[0;90m关闭\033[0m \033[0;90m(一次性显示)\033[0m"
        fi
        
        echo ""
        echo -e "\033[0;37m准备好了~ 有什么可以帮你的吗？\033[0m"
        echo -e "\033[0;90m提示: 使用 \033[1;32mcc list\033[0;90m 查看模型列表\033[0m"
        exit 0
    fi
    
    # 预设指令: list 列出模型
    if [ "$first_arg" = "list" ] || [ "$first_arg" = "-list" ] || [ "$first_arg" = "--list" ]; then
        if [ "$API_TYPE" = "ollama" ]; then
            # Ollama: 列出本地安装的模型
            local models=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}')
            if [ -z "$models" ]; then
                echo -e "\033[0;33m未找到已安装的模型\033[0m"
                echo -e "\033[0;37m使用 \033[1;32mcc -add\033[0;37m 安装新模型\033[0m"
                exit 0
            fi
            
            echo -e "\033[0;37m已安装的模型:\033[0m"
            echo ""
            while IFS= read -r model; do
                if [ "$model" = "$MODEL" ]; then
                    echo -e "  $BULLET_CURRENT \033[1;32m$model\033[0m \033[0;90m(当前)\033[0m"
                else
                    echo -e "  $BULLET $model"
                fi
            done <<< "$models"
            echo ""
            echo -e "\033[0;90m使用 \033[1;32mcc -change\033[0;90m 切换模型\033[0m"
        else
            # 其他 API: 显示 API 信息
            echo -e "\033[0;37m当前 API 配置:\033[0m"
            echo ""
            echo -e "  API 类型: \033[1;36m$API_TYPE\033[0m"
            echo -e "  API 地址: \033[0;90m$OLLAMA_URL\033[0m"
            echo -e "  当前模型: \033[1;32m$MODEL\033[0m"
            echo ""
            echo -e "\033[0;90m使用 \033[1;32mcc -config\033[0;90m 更改配置\033[0m"
        fi
        exit 0
    fi
    
    # 预设指令: testapi 测试 API 连接
    if [ "$first_arg" = "testapi" ] || [ "$first_arg" = "test-api" ] || [ "$first_arg" = "-test" ]; then
        echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo -e "\033[1;36m            API 连接测试              \033[0m"
        echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo ""
        
        echo -e "\033[0;37m当前配置:\033[0m"
        echo -e "  API 类型: \033[1;36m$API_TYPE\033[0m"
        echo -e "  API 地址: \033[0;37m$OLLAMA_URL\033[0m"
        echo -e "  模型名称: \033[1;32m$MODEL\033[0m"
        if [ -n "$API_KEY" ]; then
            echo -e "  API Key:  \033[0;37m${API_KEY:0:10}...\033[0m"
        else
            echo -e "  API Key:  \033[0;33m(未设置)\033[0m"
        fi
        echo ""
        
        echo -e "\033[0;33m正在测试连接...\033[0m"
        echo ""
        
        # 构建测试请求
        local test_data=$(jq -n \
            --arg model "$MODEL" \
            '{
                model: $model,
                messages: [
                    {role: "user", content: "hi"}
                ],
                max_tokens: 5
            }')
        
        # 发送测试请求
        local start_time=$(date +%s%N)
        local response
        if [ -n "$API_KEY" ]; then
            response=$(timeout 30 curl -s -w "\n%{http_code}" -X POST "${OLLAMA_URL}/chat/completions" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer $API_KEY" \
                -d "$test_data" 2>&1)
        elif [ "$API_TYPE" = "ollama" ]; then
            response=$(timeout 30 curl -s -w "\n%{http_code}" -X POST "${OLLAMA_URL}/chat/completions" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer ollama" \
                -d "$test_data" 2>&1)
        else
            response=$(timeout 30 curl -s -w "\n%{http_code}" -X POST "${OLLAMA_URL}/chat/completions" \
                -H "Content-Type: application/json" \
                -d "$test_data" 2>&1)
        fi
        local end_time=$(date +%s%N)
        local duration=$(( (end_time - start_time) / 1000000 ))
        
        # 分离 HTTP 状态码和响应体
        local http_code=$(echo "$response" | tail -n 1)
        local body=$(echo "$response" | sed '$d')
        
        # 检查结果
        if [ "$http_code" = "200" ]; then
            local content=$(echo "$body" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
            if [ -n "$content" ] && [ "$content" != "null" ]; then
                echo -e "\033[1;32m✓ API 连接成功！\033[0m"
                echo ""
                echo -e "\033[0;37m响应时间: \033[1;36m${duration}ms\033[0m"
                echo -e "\033[0;37m模型响应: \033[0;32m$content\033[0m"
                echo ""
                echo -e "\033[1;32m一切正常，可以使用 cc 了！\033[0m"
            else
                echo -e "\033[1;33m⚠ API 连接成功，但响应异常\033[0m"
                echo ""
                echo -e "\033[0;37mHTTP 状态码: \033[0;32m$http_code\033[0m"
                echo -e "\033[0;37m响应时间: \033[1;36m${duration}ms\033[0m"
                echo -e "\033[0;37m原始响应:\033[0m"
                echo "$body" | jq . 2>/dev/null || echo "$body"
            fi
        else
            echo -e "\033[1;31m✗ API 连接失败\033[0m"
            echo ""
            echo -e "\033[0;37mHTTP 状态码: \033[1;31m$http_code\033[0m"
            echo -e "\033[0;37m响应时间: \033[1;36m${duration}ms\033[0m"
            echo ""
            echo -e "\033[0;33m可能的原因:\033[0m"
            
            if [ "$http_code" = "000" ] || [ -z "$http_code" ]; then
                echo -e "  \033[1;31m1. 网络连接失败\033[0m"
                echo -e "     - 检查网络连接"
                echo -e "     - 检查 API 地址是否正确"
                if [ "$API_TYPE" = "ollama" ]; then
                    echo -e "     - 确认 Ollama 服务正在运行: \033[0;32mollama serve\033[0m"
                fi
            elif [ "$http_code" = "401" ]; then
                echo -e "  \033[1;31m1. API Key 无效或已过期\033[0m"
                echo -e "     - 检查 API Key 是否正确"
                echo -e "     - 使用 \033[1;32mcc -config\033[0m 重新配置"
            elif [ "$http_code" = "404" ]; then
                echo -e "  \033[1;31m1. API 地址错误\033[0m"
                echo -e "     - 检查 API_URL 配置"
                echo -e "     - 使用 \033[1;32mcc -config\033[0m 重新配置"
            elif [ "$http_code" = "429" ]; then
                echo -e "  \033[1;31m1. 请求过于频繁（限流）\033[0m"
                echo -e "     - 稍后再试"
            else
                echo -e "  \033[1;31m1. 模型名称可能不正确\033[0m"
                echo -e "     - 当前模型: \033[1;32m$MODEL\033[0m"
                echo -e "     - 检查模型名称是否支持"
                echo -e "  \033[1;31m2. API 服务异常\033[0m"
                echo -e "     - 查看错误详情（如果有）"
            fi
            
            echo ""
            echo -e "\033[0;37m错误详情:\033[0m"
            echo "$body" | jq . 2>/dev/null || echo "$body"
        fi
        
        exit 0
    fi
    
    # 预设指令: -w 工作模式
    if [ "$first_arg" = "-w" ] || [ "$first_arg" = "work" ]; then
        # 更新配置文件中的 MODE
        if [ -f "$CONFIG_FILE" ]; then
            # 使用更健壮的 sed 命令，支持各种格式
            if grep -q "^MODE=" "$CONFIG_FILE" 2>/dev/null; then
                sed -i 's/^MODE=.*/MODE="work"/' "$CONFIG_FILE"
            else
                # 如果找不到 MODE 设置，添加到文件末尾
                echo 'MODE="work"' >> "$CONFIG_FILE"
            fi
        else
            # 如果配置文件不存在，创建它
            echo 'MODE="work"' > "$CONFIG_FILE"
        fi
        # 立即更新当前会话的 MODE 变量
        MODE="work"
        echo -e "\033[1;36m已切换到工作模式\033[0m \033[0;37m- 专注命令，高效执行\033[0m"
        exit 0
    fi
    
    # 预设指令: -r 休息模式
    if [ "$first_arg" = "-r" ] || [ "$first_arg" = "rest" ] || [ "$first_arg" = "chat" ]; then
        # 更新配置文件中的 MODE
        if [ -f "$CONFIG_FILE" ]; then
            # 使用更健壮的 sed 命令，支持各种格式
            if grep -q "^MODE=" "$CONFIG_FILE" 2>/dev/null; then
                sed -i 's/^MODE=.*/MODE="rest"/' "$CONFIG_FILE"
            else
                # 如果找不到 MODE 设置，添加到文件末尾
                echo 'MODE="rest"' >> "$CONFIG_FILE"
            fi
        else
            # 如果配置文件不存在，创建它
            echo 'MODE="rest"' > "$CONFIG_FILE"
        fi
        # 立即更新当前会话的 MODE 变量
        MODE="rest"
        echo -e "\033[1;35m已切换到休息模式\033[0m \033[0;37m- 放松一下，聊聊天吧~\033[0m"
        exit 0
    fi
    
    # 预设指令: -stream 切换流式传输
    if [ "$first_arg" = "-stream" ] || [ "$first_arg" = "stream" ]; then
        # 切换流式传输状态
        if [ "$STREAM" = "true" ]; then
            new_stream="false"
            status_text="已关闭流式传输"
            desc_text="响应将一次性显示"
        else
            new_stream="true"
            status_text="已开启流式传输"
            desc_text="响应将逐字显示（仅休息模式有效）"
        fi
        
        # 更新配置文件
        if [ -f "$CONFIG_FILE" ]; then
            if grep -q "^STREAM=" "$CONFIG_FILE"; then
                sed -i "s/^STREAM=.*/STREAM=\"$new_stream\"/" "$CONFIG_FILE"
            else
                echo "STREAM=\"$new_stream\"" >> "$CONFIG_FILE"
            fi
        else
            echo "STREAM=\"$new_stream\"" >> "$CONFIG_FILE"
        fi
        
        echo -e "\033[1;36m$status_text\033[0m \033[0;37m- $desc_text\033[0m"
        echo ""
        echo -e "\033[0;90m注意: 流式传输仅在休息模式 (cc -r) 下生效\033[0m"
        echo -e "\033[0;90m工作模式需要完整命令，不支持流式传输\033[0m"
        exit 0
    fi
    
    # 预设指令: -fix 修复编码（Linux 不需要，主要用于保持接口一致性）
    if [ "$first_arg" = "-fix" ] || [ "$first_arg" = "fix" ] || [ "$first_arg" = "-fix-encoding" ]; then
        echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo -e "\033[1;36m            编码检测与修复              \033[0m"
        echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo ""
        
        # 检测当前编码
        local current_lang="$LANG"
        local locale_encoding=$(locale charmap 2>/dev/null || echo "unknown")
        
        echo -e "\033[0;37m当前系统信息:\033[0m"
        echo -e "  LANG: \033[1;32m$current_lang\033[0m"
        echo -e "  编码: \033[1;32m$locale_encoding\033[0m"
        echo ""
        
        # 检测 UTF-8 支持
        if echo "$current_lang" | grep -qi "utf"; then
            echo -e "\033[1;32m✓ 系统已配置为 UTF-8 编码\033[0m"
            echo ""
            echo -e "\033[0;37m如果你看到字符显示异常，请检查:\033[0m"
            echo -e "  1. 终端模拟器的编码设置"
            echo -e "  2. 字体是否支持 Unicode"
            echo -e "  3. locale 配置: \033[0;32mlocale\033[0m"
        else
            echo -e "\033[1;33m⚠ 系统可能未正确配置 UTF-8 编码\033[0m"
            echo ""
            echo -e "\033[0;37m建议操作:\033[0m"
            echo -e "  1. 安装 UTF-8 locale:"
            echo -e "     \033[0;32msudo locale-gen en_US.UTF-8\033[0m"
            echo -e "  2. 设置系统编码:"
            echo -e "     \033[0;32mexport LANG=en_US.UTF-8\033[0m"
            echo -e "  3. 将上述命令添加到 \033[0;32m~/.bashrc\033[0m"
        fi
        
        echo ""
        echo -e "\033[0;37mcc 当前使用的字符:\033[0m"
        echo -e "  表情: $EMOJI_HELLO"
        echo -e "  列表: $BULLET 项目1 $BULLET 项目2"
        echo -e "  当前: $BULLET_CURRENT 当前项"
        
        echo ""
        echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo -e "\033[0;37m是否要强制更新 cc 到最新版本？\033[0m"
        echo -e "\033[0;90m(编码修复后建议更新以确保所有功能正常)\033[0m"
        echo ""
        echo -ne "\033[0;33m[y/n] (默认: n): \033[0m"
        read -r update_choice < /dev/tty
        
        if [ "$update_choice" = "y" ] || [ "$update_choice" = "Y" ]; then
            echo ""
            echo -e "\033[1;36m正在强制更新...\033[0m"
            
            # 下载最新版本
            local update_url="https://raw.githubusercontent.com/jonas-pi/cc-helper/main/cc.sh"
            local temp_file="/tmp/cc_update_$$.sh"
            
            if curl -fsSL "$update_url?t=$(date +%s)" -o "$temp_file" 2>/dev/null; then
                # 备份当前版本
                cp "$HOME/cc.sh" "$HOME/cc.sh.backup" 2>/dev/null
                
                # 安装新版本
                mv "$temp_file" "$HOME/cc.sh"
                chmod +x "$HOME/cc.sh"
                
                echo -e "\033[1;32m✓ 更新完成！\033[0m"
                echo ""
                echo -e "\033[0;37m现在运行: \033[1;32mcc hello\033[0m"
            else
                echo -e "\033[1;31m✗ 更新失败\033[0m"
                echo -e "\033[0;37m请手动运行: \033[1;32mcc -u\033[0m"
            fi
        else
            echo -e "\033[0;37m已跳过更新\033[0m"
        fi
        
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
            local changelog=$(curl -fsSL "https://raw.githubusercontent.com/jonas-pi/cc-helper/main/CHANGELOG.md" 2>/dev/null | head -100)
            if [ -n "$changelog" ]; then
                # 提取当前版本的更新内容（直到遇到分隔符 --- 或下一个版本标题）
                echo "$changelog" | awk -v ver="$remote_version" '/## v/{if($0 ~ "## v"ver){flag=1; print; next} else if(flag) exit} flag'
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
        
        # 下载主脚本
        if curl -fsSL "$update_url" -o "$script_path" 2>/dev/null; then
            chmod +x "$script_path"
            echo -e "\033[1;32m✓ 主脚本更新完成\033[0m"
            
            # 更新 Tab 补全脚本
            local completion_file="$HOME/.cc-completion.bash"
            if curl -fsSL "https://raw.githubusercontent.com/jonas-pi/cc-helper/main/cc-completion.bash" -o "$completion_file" 2>/dev/null; then
                echo -e "\033[1;32m✓ Tab 补全脚本已更新\033[0m"
                
                # 检查是否已添加到 .bashrc
                if ! grep -q "source $completion_file" ~/.bashrc 2>/dev/null; then
                    echo "" >> ~/.bashrc
                    echo "# cc 命令补全" >> ~/.bashrc
                    echo "[ -f \"$completion_file\" ] && source \"$completion_file\"" >> ~/.bashrc
                    echo -e "\033[1;33m  ✓ 已添加补全到 .bashrc（需要 source ~/.bashrc 生效）\033[0m"
                fi
            else
                echo -e "\033[1;33m⚠ Tab 补全更新失败（不影响使用）\033[0m"
            fi
            
            echo ""
            echo -e "\033[0;37m现在运行: \033[1;32mcc hello\033[0m"
        else
            echo -e "\033[1;31m✗ 更新失败\033[0m"
            exit 1
        fi
        exit 0
    fi
    
    # 预设指令: -change 切换模型
    if [ "$first_arg" = "-change" ] || [ "$first_arg" = "change" ]; then
        echo -e "\033[1;36m当前配置:\033[0m"
        echo -e "  API 类型: \033[1;36m$API_TYPE\033[0m"
        echo -e "  当前模型: \033[1;32m$MODEL\033[0m"
        echo ""
        
        if [ "$API_TYPE" = "ollama" ]; then
            # Ollama: 列出本地已下载的模型
            local models=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}')
            
            if [ -z "$models" ]; then
                echo -e "\033[1;31mERROR: 未找到已安装的模型\033[0m"
                echo -e "\033[0;37m提示: 使用 \033[1;32mcc -add\033[0;37m 安装新模型\033[0m"
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
            
            # 更新已配置的模型列表（Ollama 模式下保存已下载的模型）
            local configured_models_array=()
            if [ -n "$CONFIGURED_MODELS" ]; then
                IFS=',' read -ra configured_models_array <<< "$CONFIGURED_MODELS"
            fi
            
            local found=0
            for m in "${configured_models_array[@]}"; do
                if [ "$m" = "$selected" ]; then
                    found=1
                    break
                fi
            done
            if [ $found -eq 0 ]; then
                configured_models_array+=("$selected")
            fi
            CONFIGURED_MODELS=$(IFS=','; echo "${configured_models_array[*]}")
        else
            # 云端 API: 只显示已配置的模型（从配置文件读取）
            # 解析已配置的模型列表（逗号分隔）
            local configured_models_array=()
            if [ -n "$CONFIGURED_MODELS" ]; then
                IFS=',' read -ra configured_models_array <<< "$CONFIGURED_MODELS"
            fi
            
            # 如果当前模型不在列表中，添加它
            if [ -n "$MODEL" ]; then
                local found=0
                for m in "${configured_models_array[@]}"; do
                    if [ "$m" = "$MODEL" ]; then
                        found=1
                        break
                    fi
                done
                if [ $found -eq 0 ]; then
                    configured_models_array+=("$MODEL")
                fi
            fi
            
            if [ ${#configured_models_array[@]} -eq 0 ]; then
                echo -e "\033[1;33m未找到已配置的模型\033[0m"
                echo -e "\033[0;37m提示: 使用 \033[1;32mcc -config\033[0;37m 配置 API 和模型\033[0m"
                exit 0
            fi
            
            echo -e "\033[0;37m已配置的模型:\033[0m"
            local i=1
            for model in "${configured_models_array[@]}"; do
                if [ "$model" = "$MODEL" ]; then
                    echo -e "  $i. \033[1;32m$model\033[0m (当前)"
                else
                    echo -e "  $i. $model"
                fi
                i=$((i + 1))
            done
            
            echo ""
            echo -e "  \033[0;90m0. 手动输入新模型名称\033[0m"
            echo ""
            echo -ne "\033[0;33m请选择 (序号) 或直接输入模型名称: \033[0m"
            read -r choice < /dev/tty
            
            local selected=""
            # 检查是否是序号选择
            if [[ "$choice" =~ ^[0-9]+$ ]]; then
                local index=$((choice))
                if [ $index -eq 0 ]; then
                    echo -ne "\033[0;33m输入模型名称: \033[0m"
                    read -r selected < /dev/tty
                    if [ -z "$selected" ]; then
                        echo -e "\033[1;31mERROR: 模型名称不能为空\033[0m"
                        exit 1
                    fi
                elif [ $index -gt 0 ] && [ $index -le ${#configured_models_array[@]} ]; then
                    selected="${configured_models_array[$((index - 1))]}"
                else
                    echo -e "\033[1;31mERROR: 无效的序号，请输入 0-${#configured_models_array[@]} 之间的数字\033[0m"
                    exit 1
                fi
            else
                # 直接输入模型名称，验证是否为空
                local input_model=$(echo "$choice" | xargs)
                if [ -z "$input_model" ]; then
                    echo -e "\033[1;31mERROR: 模型名称不能为空\033[0m"
                    exit 1
                fi
                # 检查是否是已知模型
                local found=0
                for m in "${configured_models_array[@]}"; do
                    if [ "$m" = "$input_model" ]; then
                        found=1
                        break
                    fi
                done
                if [ $found -eq 1 ]; then
                    selected="$input_model"
                else
                    # 允许输入新模型名称（可能是新的 API 模型）
                    selected="$input_model"
                    echo -e "\033[1;33m提示: 将使用新模型名称 '$selected'，如果这是 API 模型，请确保已正确配置 API\033[0m"
                fi
            fi
            
            if [ -z "$selected" ]; then
                echo -e "\033[1;31mERROR: 无效输入\033[0m"
                exit 1
            fi
            
            # 如果新模型不在列表中，添加到列表
            local found=0
            for m in "${configured_models_array[@]}"; do
                if [ "$m" = "$selected" ]; then
                    found=1
                    break
                fi
            done
            if [ $found -eq 0 ]; then
                configured_models_array+=("$selected")
            fi
            
            # 更新 CONFIGURED_MODELS（转换为逗号分隔的字符串）
            CONFIGURED_MODELS=$(IFS=','; echo "${configured_models_array[*]}")
        fi
        
        # 更新配置文件（包括已配置的模型列表）
        if [ -f "$CONFIG_FILE" ]; then
            if grep -q "^MODEL=" "$CONFIG_FILE" 2>/dev/null; then
                sed -i "s/^MODEL=.*/MODEL=\"$selected\"/" "$CONFIG_FILE"
            else
                echo "MODEL=\"$selected\"" >> "$CONFIG_FILE"
            fi
            
            # 更新已配置的模型列表
            if grep -q "^CONFIGURED_MODELS=" "$CONFIG_FILE" 2>/dev/null; then
                sed -i "s/^CONFIGURED_MODELS=.*/CONFIGURED_MODELS=\"$CONFIGURED_MODELS\"/" "$CONFIG_FILE"
            else
                echo "CONFIGURED_MODELS=\"$CONFIGURED_MODELS\"" >> "$CONFIG_FILE"
            fi
        else
            cat > "$CONFIG_FILE" << EOF
MODEL="$selected"
CONFIGURED_MODELS="$CONFIGURED_MODELS"
EOF
        fi
        
        echo ""
        echo -e "\033[1;32m✓ 已切换到: $selected\033[0m"
        echo ""
        echo -e "\033[0;37m提示: 使用 \033[1;32mcc testapi\033[0;37m 测试新模型连接\033[0m"
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
        
        # 更新已配置的模型列表（如果当前模型不在列表中，添加它）
        local configured_models_array=()
        if [ -n "$CONFIGURED_MODELS" ]; then
            IFS=',' read -ra configured_models_array <<< "$CONFIGURED_MODELS"
        fi
        
        local found=0
        for m in "${configured_models_array[@]}"; do
            if [ "$m" = "$MODEL" ]; then
                found=1
                break
            fi
        done
        if [ $found -eq 0 ] && [ -n "$MODEL" ]; then
            configured_models_array+=("$MODEL")
        fi
        CONFIGURED_MODELS=$(IFS=','; echo "${configured_models_array[*]}")
        
        # 保存配置
        cat > "$CONFIG_FILE" << EOF
# CC 配置文件
# 由 cc -config 自动生成

API_TYPE="$API_TYPE"
OLLAMA_URL="$OLLAMA_URL"
MODEL="$MODEL"
API_KEY="$API_KEY"
MODE="$MODE"
CONFIGURED_MODELS="$CONFIGURED_MODELS"
EOF
        
        echo ""
        echo -e "\033[1;32m✓ 配置已保存到 $CONFIG_FILE\033[0m"
        
        # 测试 API 连接
        echo ""
        echo -e "\033[0;33m正在测试 API 连接...\033[0m"
        
        local test_auth_header=""
        if [ -n "$API_KEY" ]; then
            test_auth_header="-H \"Authorization: Bearer $API_KEY\""
        elif [ "$API_TYPE" = "ollama" ]; then
            test_auth_header="-H \"Authorization: Bearer ollama\""
        fi
        
        local test_body=$(printf '{
            "model": "%s",
            "messages": [
                {"role": "user", "content": "hi"}
            ],
            "max_tokens": 5
        }' "$MODEL")
        
        local test_response=$(timeout 10 curl -s -X POST "${OLLAMA_URL}/chat/completions" \
            -H "Content-Type: application/json" \
            $test_auth_header \
            -d "$test_body" 2>&1)
        
        if [ $? -eq 0 ]; then
            local test_content=$(echo "$test_response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
            if [ -n "$test_content" ] && [ "$test_content" != "null" ]; then
                echo -e "\033[1;32m✓ API 连接成功！模型响应正常\033[0m"
            else
                echo -e "\033[0;33m⚠ API 连接成功，但模型响应异常\033[0m"
            fi
        else
            echo -e "\033[1;31m✗ API 连接失败\033[0m"
            echo -e "\033[0;33m请检查:\033[0m"
            echo -e "\033[0;37m  1. API Key 是否正确\033[0m"
            echo -e "\033[0;37m  2. 模型名称是否正确\033[0m"
            echo -e "\033[0;37m  3. 网络连接是否正常\033[0m"
        fi
        
        echo ""
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
        echo -e "\033[0;32mcc hello\033[0m       \033[0;32mcc list\033[0m        \033[0;32mcc testapi\033[0m"
        echo -e "\033[0;32mcc -w\033[0m          \033[0;32mcc -r\033[0m          \033[0;32mcc -stream\033[0m"
        echo -e "\033[0;32mcc -config\033[0m     \033[0;32mcc -change\033[0m     \033[0;32mcc -add\033[0m"
        echo -e "\033[0;32mcc -del\033[0m        \033[0;32mcc -fix\033[0m        \033[0;32mcc -u\033[0m"
        echo -e "\033[0;32mcc -h\033[0m"
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

