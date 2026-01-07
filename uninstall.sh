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

# 3. （可选）删除模型
echo -e "${YELLOW}[3/4] 检查 Ollama 模型...${NC}"
if command -v ollama &> /dev/null; then
    if ollama list 2>/dev/null | grep -q "qwen2.5:1.5b"; then
        echo -e "${YELLOW}  发现模型 qwen2.5:1.5b${NC}"
        read -p "是否删除模型？(y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            ollama rm qwen2.5:1.5b 2>/dev/null && echo -e "${GREEN}✓ 模型已删除${NC}" || echo -e "${YELLOW}  模型删除失败或不存在${NC}"
        else
            echo -e "${YELLOW}  保留模型${NC}"
        fi
    else
        echo -e "${YELLOW}  模型不存在${NC}"
    fi
else
    echo -e "${YELLOW}  Ollama 未安装${NC}"
fi
echo ""

# 4. 清理 ~/bin 目录（如果为空）
echo -e "${YELLOW}[4/4] 清理目录...${NC}"
if [ -d "$HOME/bin" ]; then
    if [ -z "$(ls -A $HOME/bin)" ]; then
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
echo -e "${YELLOW}注意：${NC}"
echo -e "- Ollama 和 jq 不会被卸载（它们是系统依赖）"
echo -e "- 如需完全卸载 Ollama，请参考 Ollama 官方文档"
echo ""

