#Requires -Version 5.1
<#
.SYNOPSIS
    Shared configuration loader for Windows System Toolkit.
.DESCRIPTION
    Loads system-profile.json, merges with hardcoded defaults, and provides
    safe nested access via Get-ProfileValue. All scripts dot-source this file.
#>

function Get-DefaultProfile {
    return @{
        System = @{
            computerName = $env:COMPUTERNAME
            osVersion    = ''
            cpu          = @{ name = ''; cores = 0; logicalProcessors = 0 }
            ram          = @{ totalGB = 0 }
            gpus         = @()
            drives       = @()
        }
        Thresholds = @{
            CPU  = @{ temperatureWarning = 80 }
            RAM  = @{ usageWarning = 85 }
            GPU  = @{ temperatureWarning = 80 }
            Disk = @{ warningFreePercent = 10; criticalFreePercent = 5 }
        }
        Services = @{
            monitoring = @(
                @{ name = 'SunshineService'; label = 'Sunshine'; processName = 'sunshine'; enabled = $true }
                @{ name = 'Tailscale'; label = 'Tailscale'; processName = 'tailscale'; enabled = $true }
                @{ name = 'com.docker.service'; label = 'Docker Desktop'; processName = 'docker'; enabled = $true }
                @{ name = 'OllamaService'; label = 'Ollama'; processName = 'ollama'; enabled = $true }
            )
        }
        Paths = @{
            SunshineConfig = '%ProgramFiles%\Sunshine\config\sunshine.conf'
            ChromeCache    = '%LOCALAPPDATA%\Google\Chrome\User Data\Default\Cache'
            EdgeCache      = '%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Cache'
        }
        Windows = @{
            updateCache  = @{ sizeThresholdMB = 500 }
            defenderScan = @{ daysBeforeWarning = 7 }
            defenderSignature = @{ maxAgeDays = 7 }
        }
        WSL = @{
            enabled = $true
            kernel  = @{ minimumMajor = 5; minimumMinor = 15 }
            disk    = @{ usageWarning = 80 }
            wslconf = @{
                interop   = @{ enabled = $true; appendWindowsPath = $true }
                systemd   = @{ enabled = $true }
                automount = @{ enabled = $true; root = '/mnt'; options = 'metadata,uid=1000,gid=1000' }
            }
            servicesToDisable = @('cloud-init', 'cloud-init-local', 'snapd', 'snapd.socket', 'snapd.seeded', 'landscape-client', 'apport')
        }
        ScheduledTasks = @{
            runAsSystem = $true
            executionTimeLimitHours = 2
            tasks = @(
                @{
                    name        = 'WST-UpdatePackages'
                    script      = 'Update-AllPackages.ps1'
                    args        = '-Auto'
                    description = 'Daily package updates (Winget + WSL apt)'
                    trigger     = @{ type = 'Daily'; time = '3:00AM' }
                }
                @{
                    name        = 'WST-RepairHealth'
                    script      = 'Repair-WindowsHealth.ps1'
                    args        = '-Auto -QuickOnly'
                    description = 'Weekly Windows health check'
                    trigger     = @{ type = 'Weekly'; time = '4:00AM'; dayOfWeek = 'Sunday' }
                }
                @{
                    name        = 'WST-SecurityAudit'
                    script      = 'Harden-Security.ps1'
                    args        = '-ReportOnly'
                    description = 'Monthly security audit report'
                    trigger     = @{ type = 'Weekly'; time = '2:00AM'; dayOfWeek = 'Sunday'; weeksInterval = 4 }
                }
                @{
                    name        = 'WST-HealthMonitor'
                    script      = 'Monitor-SystemHealth.ps1'
                    args        = '-Report'
                    description = 'Daily system health report'
                    trigger     = @{ type = 'Daily'; time = '8:00AM' }
                }
            )
        }
        Packages = @{
            winget = @{ enabled = $true }
            wsl    = @{ enabled = $true }
            pip    = @{ enabled = $true }
            exclusionsFile = 'config\excluded-packages.json'
        }
        Network = @{
            ncsiProbeUrl       = 'http://www.msftconnecttest.com/connecttest.txt'
            ncsiExpectedContent = 'Microsoft Connect Test'
            adapterPriority    = @{
                ethernet = 10
                wifi     = 50
            }
        }
        Logging = @{
            retentionDays = 30
        }
    }
}

function Expand-EnvVarsInString {
    param([string]$Value)
    if (-not $Value) { return $Value }
    return [System.Environment]::ExpandEnvironmentVariables($Value)
}

function Expand-EnvVarsInObject {
    param($Object)
    if ($Object -is [hashtable]) {
        $result = @{}
        foreach ($key in $Object.Keys) {
            $result[$key] = Expand-EnvVarsInObject $Object[$key]
        }
        return $result
    }
    elseif ($Object -is [System.Collections.IList]) {
        $result = @()
        foreach ($item in $Object) {
            $result += , (Expand-EnvVarsInObject $item)
        }
        return $result
    }
    elseif ($Object -is [string]) {
        return Expand-EnvVarsInString $Object
    }
    else {
        return $Object
    }
}

function Merge-Hashtables {
    param(
        [hashtable]$Base,
        [hashtable]$Override
    )
    $result = $Base.Clone()
    foreach ($key in $Override.Keys) {
        if ($result.ContainsKey($key) -and $result[$key] -is [hashtable] -and $Override[$key] -is [hashtable]) {
            $result[$key] = Merge-Hashtables -Base $result[$key] -Override $Override[$key]
        }
        else {
            $result[$key] = $Override[$key]
        }
    }
    return $result
}

function ConvertTo-HashtableFromJson {
    param($InputObject)
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $hash = @{}
        foreach ($prop in $InputObject.PSObject.Properties) {
            $hash[$prop.Name] = ConvertTo-HashtableFromJson $prop.Value
        }
        return $hash
    }
    elseif ($InputObject -is [System.Collections.IList]) {
        $list = @()
        foreach ($item in $InputObject) {
            $list += , (ConvertTo-HashtableFromJson $item)
        }
        return $list
    }
    else {
        return $InputObject
    }
}

function Initialize-Profile {
    param(
        [string]$ProfilePath
    )
    $defaults = Get-DefaultProfile

    if ($ProfilePath -and (Test-Path $ProfilePath)) {
        try {
            $json = Get-Content $ProfilePath -Raw -ErrorAction Stop | ConvertFrom-Json
            $overrides = ConvertTo-HashtableFromJson $json
            $merged = Merge-Hashtables -Base $defaults -Override $overrides
        }
        catch {
            Write-Warning "Failed to load profile from '$ProfilePath': $_. Using defaults."
            $merged = $defaults
        }
    }
    else {
        $merged = $defaults
    }

    if ($merged.ContainsKey('Paths')) {
        $merged['Paths'] = Expand-EnvVarsInObject $merged['Paths']
    }

    if ($merged.ContainsKey('Packages') -and $merged['Packages'].ContainsKey('exclusionsFile')) {
        $merged['Packages']['exclusionsFile'] = Expand-EnvVarsInString $merged['Packages']['exclusionsFile']
    }

    return $merged
}

function Get-ProfileValue {
    param(
        [hashtable]$Config,
        [string]$Path,
        $Default = $null
    )
    $parts = $Path -split '\.'
    $current = $Config
    foreach ($part in $parts) {
        if ($current -is [hashtable] -and $current.ContainsKey($part)) {
            $current = $current[$part]
        }
        else {
            return $Default
        }
    }
    return $current
}
