try {
    # Create new GPO
    $NewGPO = New-GPO -Name $GPOName -Domain $Domain -Comment "Azure Automation file permissions for runbooks"
    
    # Create startup script content
    $StartupScript = @"
# Set Azure Automation file permissions
`$ErrorActionPreference = "SilentlyContinue"

# Path 1: Azure Connected Machine Agent Tokens
`$Path1 = "`$env:ProgramData\AzureConnectedMachineAgent\Tokens"
if (Test-Path `$Path1) {
    takeown /f "`$Path1" /r /d y
    icacls "`$Path1" /inheritance:r
    icacls "`$Path1" /grant:r "NT AUTHORITY\SYSTEM:(OI)(CI)F"
    icacls "`$Path1" /grant:r "NT AUTHORITY\NETWORK SERVICE:(OI)(CI)R"
    icacls "`$Path1" /grant:r "$($ADUser.SamAccountName):(OI)(CI)M"
    icacls "`$Path1" /grant:r "BUILTIN\Administrators:(OI)(CI)F"
}

# Path 2: Hybrid Worker Plugin
`$Path2 = "`$env:SystemDrive\Packages\Plugins\Microsoft.Azure.Automation.HybridWorker.HybridWorkerForWindows"
if (Test-Path `$Path2) {
    takeown /f "`$Path2" /r /d y
    icacls "`$Path2" /inheritance:r
    icacls "`$Path2" /grant:r "$($ADUser.SamAccountName):(OI)(CI)M"
    icacls "`$Path2" /grant:r "NT AUTHORITY\SYSTEM:(OI)(CI)F"
    icacls "`$Path2" /grant:r "BUILTIN\Administrators:(OI)(CI)F"
}
"@

    # Create scripts directory in GPO
    $ScriptsPath = "\\$Domain\SYSVOL\$Domain\Policies\{$($NewGPO.Id)}\Machine\Scripts\Startup"
    New-Item -Path $ScriptsPath -ItemType Directory -Force
    
    # Save startup script
    $StartupScript | Out-File -FilePath "$ScriptsPath\SetAzureAutomationPermissions.ps1" -Encoding UTF8
    
    # Configure GPO to run startup script
    Set-GPRegistryValue -Name $GPOName -Key "HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Group Policy\Scripts\Startup\0" -ValueName "0CmdLine" -Type String -Value "PowerShell.exe"
    Set-GPRegistryValue -Name $GPOName -Key "HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Group Policy\Scripts\Startup\0" -ValueName "0Parameters" -Type String -Value "-ExecutionPolicy Bypass -File SetAzureAutomationPermissions.ps1"
    
    # Link GPO to OU
    New-GPLink -Name $GPOName -Target $TargetOU -LinkEnabled Yes
    
    Write-Host "GPO '$GPOName' created successfully with startup script and linked to '$TargetOU'"
    
} catch {
    Write-Error "Failed to create GPO: $($_.Exception.Message)"
}