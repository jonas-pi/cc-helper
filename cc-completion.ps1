# cc 命令 PowerShell 补全脚本

Register-ArgumentCompleter -CommandName cc -ScriptBlock {
    param($commandName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    # 所有预设命令
    $commands = @(
        'hello', 'list', 'testapi',
        '-w', 'work',
        '-r', 'rest', 'chat',
        '-stream', 'stream',
        '-config', 'config',
        '-change', 'change',
        '-add', 'add',
        '-del', 'delete', 'rm',
        '-shell', 'shell',
        '-fix',
        '-u', 'update',
        '-h', 'help'
    )
    
    # 过滤匹配的命令
    $commands | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

