# Pester tests for Windows System Toolkit
# Compatible with Pester 5.x (CI) and 3.x (local)

BeforeAll {
    $script:toolkitRoot = Split-Path $PSScriptRoot
    . (Join-Path $script:toolkitRoot "lib\Load-Profile.ps1")
    . (Join-Path $script:toolkitRoot "lib\Write-Helpers.ps1")
}

Describe "Script Syntax Validation" {
    BeforeAll {
        $script:allScripts = Get-ChildItem -Path $script:toolkitRoot -Filter "*.ps1" -Recurse
    }

    It "parses <_> without errors" -ForEach @(
        'Fix-NetworkStack.ps1', 'Fix-WSLGPU.ps1', 'Harden-Security.ps1',
        'Install-ScheduledTasks.ps1', 'Monitor-SystemHealth.ps1', 'Optimize-WSL.ps1',
        'Repair-WindowsHealth.ps1', 'Setup.ps1', 'Update-AllPackages.ps1', 'wst.ps1',
        'lib\Load-Profile.ps1', 'lib\Write-Helpers.ps1'
    ) {
        $file = Join-Path $script:toolkitRoot $_
        $tokens = $null; $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0
    }
}

Describe "Script Help Blocks" {
    It "<_> has a synopsis" -ForEach @(
        'Fix-NetworkStack.ps1', 'Fix-WSLGPU.ps1', 'Harden-Security.ps1',
        'Install-ScheduledTasks.ps1', 'Monitor-SystemHealth.ps1', 'Optimize-WSL.ps1',
        'Repair-WindowsHealth.ps1', 'Update-AllPackages.ps1', 'wst.ps1'
    ) {
        $file = Join-Path $script:toolkitRoot $_
        $help = Get-Help $file -ErrorAction SilentlyContinue
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Synopsis | Should -Not -Be $file
    }
}

Describe "Load-Profile.ps1" {
    Context "Get-DefaultProfile" {
        It "returns a hashtable with required keys" {
            $profile = Get-DefaultProfile
            $profile | Should -BeOfType [hashtable]
            $profile.ContainsKey("System") | Should -BeTrue
            $profile.ContainsKey("Thresholds") | Should -BeTrue
            $profile.ContainsKey("Services") | Should -BeTrue
            $profile.ContainsKey("Packages") | Should -BeTrue
            $profile.ContainsKey("Network") | Should -BeTrue
            $profile.ContainsKey("Logging") | Should -BeTrue
        }

        It "has valid threshold defaults" {
            $profile = Get-DefaultProfile
            $profile.Thresholds.CPU.temperatureWarning | Should -BeGreaterThan 0
            $profile.Thresholds.RAM.usageWarning | Should -BeGreaterThan 0
            $profile.Thresholds.Disk.criticalFreePercent | Should -BeLessThan $profile.Thresholds.Disk.warningFreePercent
        }

        It "has 4 scheduled tasks defined" {
            $profile = Get-DefaultProfile
            $profile.ScheduledTasks.tasks.Count | Should -Be 4
        }

        It "has network config defaults" {
            $profile = Get-DefaultProfile
            $profile.Network.ncsiProbeUrl | Should -Not -BeNullOrEmpty
            $profile.Network.adapterPriority.ethernet | Should -Be 10
        }
    }

    Context "Get-ProfileValue" {
        BeforeAll {
            $script:testConfig = @{
                Level1 = @{
                    Level2 = @{ Value = 42 }
                    Simple = "hello"
                }
            }
        }

        It "resolves nested paths" {
            Get-ProfileValue $script:testConfig "Level1.Level2.Value" | Should -Be 42
        }

        It "resolves simple paths" {
            Get-ProfileValue $script:testConfig "Level1.Simple" | Should -Be "hello"
        }

        It "returns default for missing paths" {
            Get-ProfileValue $script:testConfig "Level1.Missing.Path" "fallback" | Should -Be "fallback"
        }

        It "returns null for missing paths with no default" {
            Get-ProfileValue $script:testConfig "Nonexistent" | Should -BeNullOrEmpty
        }
    }

    Context "Initialize-Profile" {
        It "returns defaults when no profile file exists" {
            $config = Initialize-Profile -ProfilePath "C:\nonexistent\path.json"
            $config | Should -BeOfType [hashtable]
            $config.Thresholds.CPU.temperatureWarning | Should -Be 80
        }
    }

    Context "Merge-Hashtables" {
        It "merges overrides into base" {
            $base = @{ A = 1; B = @{ C = 2; D = 3 } }
            $override = @{ B = @{ C = 99 } }
            $result = Merge-Hashtables -Base $base -Override $override
            $result.A | Should -Be 1
            $result.B.C | Should -Be 99
            $result.B.D | Should -Be 3
        }

        It "adds new keys from override" {
            $base = @{ A = 1 }
            $override = @{ B = 2 }
            $result = Merge-Hashtables -Base $base -Override $override
            $result.A | Should -Be 1
            $result.B | Should -Be 2
        }
    }
}

Describe "Write-Helpers.ps1" {
    Context "Test-IsAdmin" {
        It "returns a boolean" {
            $result = Test-IsAdmin
            $result | Should -BeOfType [bool]
        }
    }

    Context "Initialize-Log" {
        It "creates a log file path with correct format" {
            $path = Initialize-Log -ScriptPath (Join-Path $script:toolkitRoot "Test-Script.ps1") -RootPath $script:toolkitRoot
            $path | Should -Match "Test-Script_\d{6}\.log$"
            $path | Should -Match "logs"
        }

        It "creates the log directory" {
            $path = Initialize-Log -ScriptPath (Join-Path $script:toolkitRoot "Test-Script.ps1") -RootPath $script:toolkitRoot
            $dir = Split-Path $path
            Test-Path $dir | Should -BeTrue
        }
    }
}

Describe "wst.ps1 CLI" {
    It "returns help text for 'help' command" {
        $wstPath = Join-Path $script:toolkitRoot "wst.ps1"
        $output = & pwsh -NoProfile -ExecutionPolicy Bypass -File $wstPath help 2>&1
        $outputText = $output -join "`n"
        $outputText | Should -Match "Windows System Toolkit"
        $outputText | Should -Match "COMMANDS"
    }

    It "exits with error for unknown command" {
        $wstPath = Join-Path $script:toolkitRoot "wst.ps1"
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $wstPath nonexistent 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
    }
}

Describe "Config Files" {
    It "excluded-packages.json is valid JSON" {
        $path = Join-Path $script:toolkitRoot "config\excluded-packages.json"
        { Get-Content $path -Raw | ConvertFrom-Json } | Should -Not -Throw
    }
}
