#!/bin/bash
# cc 命令 Bash 补全脚本

_cc_completion() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    # 所有预设命令（统一使用 - 前缀格式）
    opts="-hello --hello -list --list -testapi -test -w --work -r --rest --chat -stream --stream -fix --fix -fix-encoding -shell --shell -u --update -update -change --change -add --add -config --config -del --del -delete -rm -setup --setup -h --help -help"
    
    # 如果当前词以 - 开头或为空，提供补全
    if [[ ${cur} == -* ]] || [[ ${COMP_CWORD} -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
        return 0
    fi
}

# 注册补全函数
complete -F _cc_completion cc


