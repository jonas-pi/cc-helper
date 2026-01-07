#!/bin/bash

# cc 命令助手卸载脚本

# 颜色定义
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  卸载 cc 命令助手${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 1. 删除脚本文件
echo -e "${YELLOW}[1/4] 删除脚本文件...${NC}"
if [ -f "$HOME/cc.sh" ]; then
    rm -f "$HOME/cc.sh"
    echo -e "${GREEN}✓ 已删除 ~/cc.sh${NC}"
else
    echo -e "${YELLOW}  ~/cc.sh 不存在${NC}"
fi

if [ -f "$HOME/bin/cc" ]; then
    rm -f "$HOME/bin/cc"
    echo -e "${GREEN}✓ 已删除 ~/bin/cc${NC}"
else
    echo -e "${YELLOW}  ~/bin/cc 不存在${NC}"
fi
echo ""

# 2. 从 .bashrc 中移除配置
echo -e "${YELLOW}[2/4] 从 .bashrc 中移除配置...${NC}"
BASHRC="$HOME/.bashrc"
if [ -f "$BASHRC" ]; then
    # 备份 .bashrc
    cp "$BASHRC" "$BASHRC.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    
    # 移除 cc 命令助手配置
    if grep -q "# cc 命令助手配置" "$BASHRC" 2>/dev/null; then
        sed -i '/# cc 命令助手配置/,+2d' "$BASHRC"
        echo -e "${GREEN}✓ 已移除 PATH 配置${NC}"
    fi
    
    # 移除别名
    if grep -q "alias cc=" "$BASHRC" 2>/dev/null; then
        sed -i '/alias cc=/d' "$BASHRC"
        echo -e "${GREEN}✓ 已移除 cc 别名${NC}"
    fi
    
    echo -e "${GREEN}✓ .bashrc 已清理${NC}"
else
    echo -e "${YELLOW}  .bashrc 不存在${NC}"
fi
echo ""

# 3. 删除模型
echo -e "${YELLOW}[3/6] 删除 Ollama 模型...${NC}"
if command -v ollama &> /dev/null; then
    # 停止 Ollama 服务
    if pgrep -x ollama > /dev/null 2>&1; then
        echo -e "${YELLOW}  停止 Ollama 服务...${NC}"
        pkill -x ollama 2>/dev/null || true
        sleep 1
    fi
    
    # 删除模型
    if ollama list 2>/dev/null | grep -q "qwen2.5:1.5b"; then
        echo -e "${YELLOW}  正在删除模型 qwen2.5:1.5b...${NC}"
        if ollama rm qwen2.5:1.5b 2>/dev/null; then
            echo -e "${GREEN}✓ 模型已删除${NC}"
        else
            echo -e "${YELLOW}  模型删除失败，可能正在使用中${NC}"
        fi
    else
        echo -e "${YELLOW}  模型不存在，跳过${NC}"
    fi
else
    echo -e "${YELLOW}  Ollama 未安装，跳过${NC}"
fi
echo ""

# 4. 卸载 Ollama
echo -e "${YELLOW}[4/6] 卸载 Ollama...${NC}"

# 停止所有 Ollama 进程（无论命令是否存在）
if pgrep -x ollama > /dev/null 2>&1; then
    echo -e "${YELLOW}  停止 Ollama 服务进程...${NC}"
    # 尝试优雅停止
    pkill -x ollama 2>/dev/null || true
    sleep 2
    # 如果还在运行，强制停止
    if pgrep -x ollama > /dev/null 2>&1; then
        pkill -9 -x ollama 2>/dev/null || true
        sleep 1
    fi
    echo -e "${GREEN}✓ Ollama 进程已停止${NC}"
fi

# 查找并删除 Ollama 二进制文件（多个可能位置）
OLLAMA_PATHS=(
    "/usr/local/bin/ollama"
    "/usr/bin/ollama"
    "$HOME/.local/bin/ollama"
    "$(which ollama 2>/dev/null)"
)

OLLAMA_FOUND=0
for path in "${OLLAMA_PATHS[@]}"; do
    if [ -n "$path" ] && [ -f "$path" ]; then
        echo -e "${YELLOW}  发现 Ollama: ${path}${NC}"
        if sudo rm -f "$path" 2>/dev/null; then
            echo -e "${GREEN}✓ 已删除 ${path}${NC}"
            OLLAMA_FOUND=1
        else
            echo -e "${YELLOW}  需要 sudo 权限删除 ${path}${NC}"
            echo -e "${YELLOW}  请手动运行: sudo rm -f ${path}${NC}"
        fi
    fi
done

# 删除 Ollama 数据目录（多个可能位置）
OLLAMA_DATA_DIRS=(
    "$HOME/.ollama"
    "/usr/local/share/ollama"
    "/var/lib/ollama"
)

for dir in "${OLLAMA_DATA_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo -e "${YELLOW}  发现数据目录: ${dir}${NC}"
        if [ "$dir" = "$HOME/.ollama" ]; then
            rm -rf "$dir" && echo -e "${GREEN}✓ 已删除 ${dir}${NC}"
        else
            if sudo rm -rf "$dir" 2>/dev/null; then
                echo -e "${GREEN}✓ 已删除 ${dir}${NC}"
            else
                echo -e "${YELLOW}  需要 sudo 权限删除 ${dir}${NC}"
                echo -e "${YELLOW}  请手动运行: sudo rm -rf ${dir}${NC}"
            fi
        fi
    fi
done

# 删除 systemd 服务（如果存在）
if [ -f "/etc/systemd/system/ollama.service" ] || [ -f "$HOME/.config/systemd/user/ollama.service" ]; then
    echo -e "${YELLOW}  发现 systemd 服务，正在禁用...${NC}"
    sudo systemctl stop ollama 2>/dev/null || systemctl --user stop ollama 2>/dev/null || true
    sudo systemctl disable ollama 2>/dev/null || systemctl --user disable ollama 2>/dev/null || true
    sudo rm -f /etc/systemd/system/ollama.service 2>/dev/null || rm -f "$HOME/.config/systemd/user/ollama.service" 2>/dev/null || true
    sudo systemctl daemon-reload 2>/dev/null || systemctl --user daemon-reload 2>/dev/null || true
    echo -e "${GREEN}✓ systemd 服务已移除${NC}"
fi

if [ $OLLAMA_FOUND -eq 0 ] && ! pgrep -x ollama > /dev/null 2>&1; then
    echo -e "${YELLOW}  Ollama 未找到或已卸载${NC}"
fi
echo ""

# 5. 清理临时文件和日志
echo -e "${YELLOW}[5/6] 清理临时文件和日志...${NC}"
TEMP_FILES=(
    "/tmp/cc-install.log"
    "/tmp/ollama.log"
    "/tmp/ollama_install.log"
    "/tmp/spinner.log"
)

for file in "${TEMP_FILES[@]}"; do
    if [ -f "$file" ]; then
        rm -f "$file" && echo -e "${GREEN}✓ 已删除 ${file}${NC}" || true
    fi
done
echo ""

# 6. 清理 ~/bin 目录（如果为空）
echo -e "${YELLOW}[6/6] 清理目录...${NC}"
if [ -d "$HOME/bin" ]; then
    if [ -z "$(ls -A $HOME/bin 2>/dev/null)" ]; then
        rmdir "$HOME/bin" 2>/dev/null && echo -e "${GREEN}✓ 已删除空目录 ~/bin${NC}" || echo -e "${YELLOW}  ~/bin 目录不为空，保留${NC}"
    else
        echo -e "${YELLOW}  ~/bin 目录不为空，保留${NC}"
    fi
fi
echo ""

# 完成
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}卸载完成！${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}下一步：${NC}"
echo -e "1. 运行以下命令重新加载配置："
echo -e "   ${GREEN}source ~/.bashrc${NC}"
echo ""
echo -e "2. 或者重新打开终端"
echo ""
echo -e "${YELLOW}已清除的内容：${NC}"
echo -e "  ✓ 脚本文件 (~/cc.sh, ~/bin/cc)"
echo -e "  ✓ 配置文件 (.bashrc 中的配置和别名)"
echo -e "  ✓ Ollama 模型 (qwen2.5:1.5b)"
echo -e "  ✓ Ollama 程序和数据目录"
echo -e "  ✓ 临时文件和日志"
echo ""
echo -e "${YELLOW}注意：${NC}"
echo -e "- jq 不会被卸载（它是系统依赖）"
echo -e "- .bashrc 备份已保存为: ${BASHRC}.backup.*"
echo -e "- 如需重新安装，请运行安装脚本"
echo ""

