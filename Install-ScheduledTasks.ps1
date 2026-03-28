[CmdletBinding()]
param(
    [switch]$Auto,
    [ValidateSet('Install','Remove','Status','Test')]
    [string]$Action = 'Status'
)
$ErrorActionPreference = "Continue"

# --- Load shared modules ---
. (Join-Path $PSScriptRoot "lib\Load-Profile.ps1")
. (Join-Path $PSScriptRoot "lib\Write-Helpers.ps1")
$config = Initialize-Profile -ProfilePath (Join-Path $PSScriptRoot "config\system-profile.json")
$logFile = Initialize-Log -ScriptPath $PSCommandPath -RootPath $PSScriptRoot

Write-Banner -Title "Scheduled Tasks Manager"

if (-not (Test-IsAdmin)) {
    Write-Bad "This script must be run as Administrator"
    exit 1
}
Write-Good "Administrator check passed"

$configTasks = Get-ProfileValue $config "ScheduledTasks.tasks" @()
$tasks = @()
foreach ($ct in $configTasks) {
    $triggerParams = @{}
    switch ($ct.trigger.type) {
        'Daily' {
            $triggerParams = @{ Daily = $true; At = $ct.trigger.time }
        }
        'Weekly' {
            $triggerParams = @{ Weekly = $true; DaysOfWeek = $ct.trigger.dayOfWeek; At = $ct.trigger.time }
            if ($ct.trigger.weeksInterval) { $triggerParams['WeeksInterval'] = $ct.trigger.weeksInterval }
        }
    }
    $tasks += @{
        Name        = $ct.name
        Script      = $ct.script
        Args        = $ct.args
        Description = $ct.description
        Trigger     = New-ScheduledTaskTrigger @triggerParams
    }
}

if ($Action -eq 'Install') {
    Write-Host ""
    Write-Host "  ACTION: Install Scheduled Tasks" -ForegroundColor Green
    Write-Host ""

    if (-not $Auto) {
        Write-Host "    [1] Install all tasks" -ForegroundColor Cyan
        Write-Host "    [2] Install individual task" -ForegroundColor Cyan
        Write-Host "    [3] Cancel" -ForegroundColor Cyan
        Write-Host ""
        $installChoice = Read-Host "    Select option [1-3]"
        if ($installChoice -eq '3') { exit 0 }
    } else {
        $installChoice = '1'
    }

    $taskList = if ($installChoice -eq '2') {
        Write-Host ""
        $i = 1
        foreach ($t in $tasks) {
            Write-Host "    [$i] $($t.Name) - $($t.Description)" -ForegroundColor Cyan
            $i++
        }
        Write-Host ""
        $sel = Read-Host "    Select task number to install"
        @($tasks[[int]$sel - 1])
    } else {
        $tasks
    }

    foreach ($task in $taskList) {
        $scriptPath = Join-Path $PSScriptRoot $task.Script
        if (-not (Test-Path $scriptPath)) {
            Write-Warn "Script not found: $scriptPath"
            continue
        }
        $taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -NonInteractive -File `"$scriptPath`" $($task.Args)"
        $runAsSystem = Get-ProfileValue $config "ScheduledTasks.runAsSystem" $true
        $timeLimitHrs = Get-ProfileValue $config "ScheduledTasks.executionTimeLimitHours" 2
        $userId = if ($runAsSystem) { 'SYSTEM' } else { [System.Security.Principal.WindowsIdentity]::GetCurrent().Name }
        $taskPrincipal = New-ScheduledTaskPrincipal -UserId $userId -RunLevel Highest -LogonType ServiceAccount
        $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours $timeLimitHrs)

        $existingTask = Get-ScheduledTask -TaskName $task.Name -ErrorAction SilentlyContinue
        if ($existingTask) {
            Set-ScheduledTask -TaskName $task.Name -Action $taskAction -Trigger $task.Trigger -Principal $taskPrincipal -Settings $taskSettings | Out-Null
            Write-Info "Updated task: $($task.Name)"
        } else {
            Register-ScheduledTask -TaskName $task.Name -Action $taskAction -Trigger $task.Trigger -Principal $taskPrincipal -Settings $taskSettings -Description $task.Description | Out-Null
            Write-Good "Installed task: $($task.Name)"
        }
    }
    Write-Host ""
    Write-Good "Install complete"
}

if ($Action -eq 'Remove') {
    Write-Host ""
    Write-Host "  ACTION: Remove Scheduled Tasks" -ForegroundColor Red
    Write-Host ""

    foreach ($task in $tasks) {
        $existingTask = Get-ScheduledTask -TaskName $task.Name -ErrorAction SilentlyContinue
        if ($existingTask) {
            Unregister-ScheduledTask -TaskName $task.Name -Confirm:$false
            Write-Good "Removed: $($task.Name)"
        } else {
            Write-Warn "Not found: $($task.Name)"
        }
    }
    Write-Host ""
    Write-Good "Remove complete"
}

if ($Action -eq 'Status') {
    Write-Host ""
    Write-Host "  ACTION: Task Status" -ForegroundColor Cyan
    Write-Host ""

    foreach ($task in $tasks) {
        $taskInfo = Get-ScheduledTask -TaskName $task.Name -ErrorAction SilentlyContinue
        if ($taskInfo) {
            $taskInfo2 = Get-ScheduledTaskInfo -TaskName $task.Name -ErrorAction SilentlyContinue
            $state = $taskInfo.State
            $lastRun = if ($taskInfo2.LastRunTime -and $taskInfo2.LastRunTime -ne '1/1/0001 12:00:00 AM') { $taskInfo2.LastRunTime.ToString('yyyy-MM-dd HH:mm:ss') } else { 'Never' }
            $lastResult = $taskInfo2.LastTaskResult
            $nextRun = if ($taskInfo2.NextRunTime -and $taskInfo2.NextRunTime -ne '1/1/0001 12:00:00 AM') { $taskInfo2.NextRunTime.ToString('yyyy-MM-dd HH:mm:ss') } else { 'Not scheduled' }

            $color = switch ($state) {
                'Running' { 'Green' }
                'Ready' { 'Cyan' }
                'Disabled' { 'Yellow' }
                default { 'White' }
            }

            Write-Host "  $($task.Name)" -ForegroundColor $color
            Write-Data "  State: $state | LastRun: $lastRun | Result: $lastResult | NextRun: $nextRun"
        } else {
            Write-Warn "$($task.Name) - Not registered"
        }
    }
}

if ($Action -eq 'Test') {
    Write-Host ""
    Write-Host "  ACTION: Test Scheduled Tasks" -ForegroundColor Yellow
    Write-Host ""

    foreach ($task in $tasks) {
        Write-Host "  Testing: $($task.Name)" -ForegroundColor Cyan
        try {
            Start-ScheduledTask -TaskName $task.Name -ErrorAction Stop
            Write-Info "Started: $($task.Name)"
        } catch {
            Write-Bad "Failed to start: $($task.Name) - $_"
        }
    }

    Start-Sleep -Seconds 5

    Write-Host ""
    Write-Host "  Test Results:" -ForegroundColor Yellow

    foreach ($task in $tasks) {
        $taskInfo = Get-ScheduledTask -TaskName $task.Name -ErrorAction SilentlyContinue
        if ($taskInfo) {
            $taskInfo2 = Get-ScheduledTaskInfo -TaskName $task.Name -ErrorAction SilentlyContinue
            $state = $taskInfo.State
            $lastResult = $taskInfo2.LastTaskResult

            $color = if ($state -eq 'Running' -or $lastResult -eq 0) { 'Green' } else { 'Yellow' }
            Write-Host "  $($task.Name) - State: $state | Result: $lastResult" -ForegroundColor $color
        }
    }
}

$logsPath = Join-Path $PSScriptRoot "logs"
if (Test-Path $logsPath) {
    $retentionDays = Get-ProfileValue $config "Logging.retentionDays" 30
    $cutoff = (Get-Date).AddDays(-$retentionDays)
    Get-ChildItem -Path $logsPath -File -Filter "*.log" | Where-Object { $_.LastWriteTime -lt $cutoff } | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Info "Cleaned up logs older than $retentionDays days"
}

Write-Host ""
Write-Info "Log: $logFile"
Wait-OrExit -Auto:$Auto
