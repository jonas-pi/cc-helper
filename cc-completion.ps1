# cc 命令 PowerShell 补全脚本

Register-ArgumentCompleter -CommandName cc -ScriptBlock {
    param($commandName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    # 所有预设命令（统一使用 - 前缀格式）
    $commands = @(
        '-hello', '--hello',
        '-list', '--list',
        '-testapi', '-test',
        '-w', '--work',
        '-r', '--rest', '--chat',
        '-stream', '--stream',
        '-fix', '--fix', '-fix-encoding',
        '-shell', '--shell',
        '-u', '--update', '-update',
        '-change', '--change',
        '-add', '--add',
        '-config', '--config',
        '-del', '--del', '-delete', '-rm',
        '-setup', '--setup',
        '-h', '--help', '-help'
    )
    
    # 过滤匹配的命令
    $commands | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}


