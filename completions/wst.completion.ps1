<#
.SYNOPSIS
    Tab completion for wst.ps1. Add to your PowerShell profile for global completion.
.DESCRIPTION
    Dot-source this file or add the following line to your $PROFILE:
      . "C:\path\to\Windows-System-Toolkit\completions\wst.completion.ps1"
#>

Register-ArgumentCompleter -CommandName 'wst.ps1' -ParameterName 'Command' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    $commands = @(
        @{ Name = 'monitor';  Desc = 'System health dashboard' }
        @{ Name = 'update';   Desc = 'Update packages (Winget, apt, pip)' }
        @{ Name = 'repair';   Desc = 'Windows health repair (DISM, SFC)' }
        @{ Name = 'security'; Desc = 'Security audit and hardening' }
        @{ Name = 'network';  Desc = 'Network diagnostics and fix' }
        @{ Name = 'wsl';      Desc = 'WSL2 optimization' }
        @{ Name = 'wslgpu';   Desc = 'WSL2 GPU passthrough diagnostics and fix' }
        @{ Name = 'tasks';    Desc = 'Scheduled tasks manager' }
        @{ Name = 'setup';    Desc = 'Configuration wizard' }
        @{ Name = 'diag';     Desc = 'Run all diagnostics' }
        @{ Name = 'status';   Desc = 'Quick system overview' }
        @{ Name = 'logs';     Desc = 'View recent log files' }
        @{ Name = 'help';     Desc = 'Show help' }
    )
    $commands | Where-Object { $_.Name -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new(
            $_.Name, $_.Name, 'ParameterValue', $_.Desc
        )
    }
}
