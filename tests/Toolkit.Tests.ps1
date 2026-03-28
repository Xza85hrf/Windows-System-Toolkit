# Pester tests for Windows System Toolkit
# Compatible with Pester 3.x (built-in) and 5.x

$toolkitRoot = Split-Path $PSScriptRoot

Describe "Script Syntax Validation" {
    $scripts = Get-ChildItem -Path $toolkitRoot -Filter "*.ps1" -Recurse

    foreach ($script in $scripts) {
        It "parses $($script.Name) without errors" {
            $tokens = $null; $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script.FullName, [ref]$tokens, [ref]$errors
            )
            $errors.Count | Should Be 0
        }
    }
}

Describe "Script Help Blocks" {
    $rootScripts = Get-ChildItem -Path $toolkitRoot -Filter "*.ps1" -Depth 0 |
        Where-Object { $_.Name -ne "Setup.ps1" }

    foreach ($script in $rootScripts) {
        It "$($script.Name) has a synopsis" {
            $help = Get-Help $script.FullName -ErrorAction SilentlyContinue
            $help.Synopsis | Should Not BeNullOrEmpty
            $help.Synopsis | Should Not Be $script.FullName
        }
    }
}

Describe "Load-Profile.ps1" {
    . (Join-Path $toolkitRoot "lib\Load-Profile.ps1")

    Context "Get-DefaultProfile" {
        It "returns a hashtable with required keys" {
            $profile = Get-DefaultProfile
            $profile | Should BeOfType [hashtable]
            $profile.ContainsKey("System") | Should Be $true
            $profile.ContainsKey("Thresholds") | Should Be $true
            $profile.ContainsKey("Services") | Should Be $true
            $profile.ContainsKey("Packages") | Should Be $true
            $profile.ContainsKey("Network") | Should Be $true
            $profile.ContainsKey("Logging") | Should Be $true
        }

        It "has valid threshold defaults" {
            $profile = Get-DefaultProfile
            $profile.Thresholds.CPU.temperatureWarning | Should BeGreaterThan 0
            $profile.Thresholds.RAM.usageWarning | Should BeGreaterThan 0
            $profile.Thresholds.Disk.criticalFreePercent | Should BeLessThan $profile.Thresholds.Disk.warningFreePercent
        }

        It "has 4 scheduled tasks defined" {
            $profile = Get-DefaultProfile
            $profile.ScheduledTasks.tasks.Count | Should Be 4
        }

        It "has network config defaults" {
            $profile = Get-DefaultProfile
            $profile.Network.ncsiProbeUrl | Should Not BeNullOrEmpty
            $profile.Network.adapterPriority.ethernet | Should Be 10
        }
    }

    Context "Get-ProfileValue" {
        $testConfig = @{
            Level1 = @{
                Level2 = @{ Value = 42 }
                Simple = "hello"
            }
        }

        It "resolves nested paths" {
            Get-ProfileValue $testConfig "Level1.Level2.Value" | Should Be 42
        }

        It "resolves simple paths" {
            Get-ProfileValue $testConfig "Level1.Simple" | Should Be "hello"
        }

        It "returns default for missing paths" {
            Get-ProfileValue $testConfig "Level1.Missing.Path" "fallback" | Should Be "fallback"
        }

        It "returns null for missing paths with no default" {
            Get-ProfileValue $testConfig "Nonexistent" | Should BeNullOrEmpty
        }
    }

    Context "Initialize-Profile" {
        It "returns defaults when no profile file exists" {
            $config = Initialize-Profile -ProfilePath "C:\nonexistent\path.json"
            $config | Should BeOfType [hashtable]
            $config.Thresholds.CPU.temperatureWarning | Should Be 80
        }
    }

    Context "Merge-Hashtables" {
        It "merges overrides into base" {
            $base = @{ A = 1; B = @{ C = 2; D = 3 } }
            $override = @{ B = @{ C = 99 } }
            $result = Merge-Hashtables -Base $base -Override $override
            $result.A | Should Be 1
            $result.B.C | Should Be 99
            $result.B.D | Should Be 3
        }

        It "adds new keys from override" {
            $base = @{ A = 1 }
            $override = @{ B = 2 }
            $result = Merge-Hashtables -Base $base -Override $override
            $result.A | Should Be 1
            $result.B | Should Be 2
        }
    }
}

Describe "Write-Helpers.ps1" {
    . (Join-Path $toolkitRoot "lib\Write-Helpers.ps1")

    Context "Test-IsAdmin" {
        It "returns a boolean" {
            $result = Test-IsAdmin
            ($result -is [bool]) | Should Be $true
        }
    }

    Context "Initialize-Log" {
        It "creates a log file path with correct format" {
            $path = Initialize-Log -ScriptPath (Join-Path $toolkitRoot "Test-Script.ps1") -RootPath $toolkitRoot
            $path | Should Match "Test-Script_\d{6}\.log$"
            $path | Should Match "logs"
        }

        It "creates the log directory" {
            $path = Initialize-Log -ScriptPath (Join-Path $toolkitRoot "Test-Script.ps1") -RootPath $toolkitRoot
            $dir = Split-Path $path
            (Test-Path $dir) | Should Be $true
        }
    }
}

Describe "wst.ps1 CLI" {
    It "returns help text for 'help' command" {
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $toolkitRoot "wst.ps1") help 2>&1
        $outputText = $output -join "`n"
        $outputText | Should Match "Windows System Toolkit"
        $outputText | Should Match "COMMANDS"
    }

    It "exits with error for unknown command" {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $toolkitRoot "wst.ps1") nonexistent 2>&1 | Out-Null
        $LASTEXITCODE | Should Be 1
    }
}

Describe "Config Files" {
    It "excluded-packages.json is valid JSON" {
        $path = Join-Path $toolkitRoot "config\excluded-packages.json"
        { Get-Content $path -Raw | ConvertFrom-Json } | Should Not Throw
    }
}
