<#
.SYNOPSIS
Install apps with Winget through Intune or SCCM.
Can be used standalone.

.DESCRIPTION
Allow to run Winget in System Context to install your apps.
https://github.com/Romanitho/Winget-Install

# More ideas from
https://github.com/djust270/Intune-Scripts/blob/master/Winget-InstallPackage.ps1

.NOTES
    File Name      : winget-install.ps1
    Version        : 1.0
    Author         : Tobias Schüle - https://justinn.io
    Prerequisite   : Windows PowerShell v5.x, Winget

.PARAMETER AppIDs
Forward Winget App ID to install. For multiple apps, separate with ","

.PARAMETER Uninstall
To uninstall app. Works with AppIDs

.PARAMETER LogPath
Used to specify logpath. Default is same folder as Winget-Autoupdate project

.PARAMETER WAUWhiteList
Adds the app to the Winget-AutoUpdate White List. More info: https://github.com/Romanitho/Winget-AutoUpdate
If '-Uninstall' is used, it removes the app from WAU White List.

.EXAMPLE
.\winget-install.ps1 -AppIDs 7zip.7zip

.EXAMPLE
.\winget-install.ps1 -AppIDs 7zip.7zip -Uninstall

.EXAMPLE
.\winget-install.ps1 -AppIDs 7zip.7zip -WAUWhiteList

.EXAMPLE
.\winget-install.ps1 -AppIDs 7zip.7zip,notepad++.notepad++ -LogPath "C:\temp\logs"

.EXAMPLE
."%systemroot%\sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File winget-install.ps1 -AppIDs Notepad++.Notepad++

.EXAMPLE
."%systemroot%\sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File winget-install.ps1 -AppIDs Notepad++.Notepad++ -CustomArgs "/ALLUSERS"
#>



[CmdletBinding()]
param(
    [Parameter(Mandatory = $True, ParameterSetName = 'AppIDs')] [String[]] $AppIDs,
    [Parameter(Mandatory = $False)] [Switch] $Uninstall,
    [Parameter(Mandatory = $False)] [Switch] $WAUWhiteList,
    [Parameter(Mandatory = $False)] [String] $WingetArgs,
    [Parameter(Mandatory = $False)] [String] $CustomArgs,
    [Parameter(Mandatory = $False)] [String] $OverrideArgs,
    [Parameter(Mandatory = $False)] [String] $Scope = 'Machine'
)


<# FUNCTIONS #>

# Initialization
function Start-Init {
    $DateTime = Get-Date -Format 'yyyyMM_ddHHmmss'

    Start-Transcript -Path "$env:ProgramData\Winget-Install\$AppIDs\$DateTime-Transcript.log" -IncludeInvocationHeader -Force

    # Config console output encoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
  
    # Logs initialisation
    if (!(Test-Path "$env:ProgramData\Winget-Install\$AppIDs\")) {
        New-Item -ItemType Directory -Force -Path "$env:ProgramData\Winget-Install\$AppIDs\" | Out-Null
    }

    # Log file
    if ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        $Script:LogFile = "$env:ProgramData\Winget-Install\$AppIDs\$DateTime-Script-SystemContext.log"
    }
    else {
        $Script:LogFile = "$env:ProgramData\Winget-Install\$AppIDs\$DateTime-Script-UserContext.log"
    }
    $Script:LogFileWingetExe = "$env:ProgramData\Winget-Install\$AppIDs\$DateTime-WingetLog.log"

    # Log Header
    if ($Uninstall) {
        Write-Log "###   $(Get-Date -Format (Get-Culture).DateTimeFormat.ShortDatePattern) - NEW UNINSTALL REQUEST   ###" 'Magenta'
    }
    else {
        Write-Log "###   $(Get-Date -Format (Get-Culture).DateTimeFormat.ShortDatePattern) - NEW INSTALL REQUEST   ###" 'Magenta'
    }

}

# Log Function
function Write-Log ($LogMsg, $LogColor = 'White') {
    # Get log
    $Log = "$(Get-Date -UFormat '%T') - $LogMsg"
    # Echo log
    $Log | Write-Host -ForegroundColor $LogColor
    # Write log to file
    $Log | Out-File -FilePath $LogFile -Append
}

# Get WinGet Location Function
function Get-WingetCmd {
    #Get WinGet Path (if admin context)
    $ResolveWingetPath = Resolve-Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_*__8wekyb3d8bbwe" | Sort-Object { [version]($_.Path -replace '^[^\d]+_((\d+\.)*\d+)_.*', '$1') }
    if ($ResolveWingetPath) {
        #If multiple versions, pick last one
        $WingetPath = $ResolveWingetPath[-1].Path
    }
    #Get WinGet Location in User context
    $WingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($WingetCmd) {
        $Script:Winget = $WingetCmd.Source
    }
    #Get Winget Location in System context
    elseif (Test-Path "$WingetPath\winget.exe") {
        $Script:Winget = "$WingetPath\winget.exe"
    }
    else {
        Write-Log 'Winget not installed or detected !' 'Red'
        break
    }
    Write-Log "Using following Winget Cmd: $winget`n"
}

#Install function
function Install-App ($AppID, $WingetArgs, $CustomArgs, $OverrideArgs, $Scope) {
    if ($CustomArgs) {
        $CustomArgs = "--custom `"$CustomArgs`""
    }

    if ($OverrideArgs) {
        $OverrideArgs = "--override `"$OverrideArgs`""
    }

    #Install App
    Write-Log "-> Installing $AppID..." 'Yellow'
    $InstallArgs = "install --id $AppID --Scope $Scope --exact --accept-package-agreements --accept-source-agreements --silent $WingetArgs $CustomArgs $OverrideArgs"
    Write-Log "-> Install parameter: $InstallArgs" 'Yellow'
    Start-Process -FilePath "$Winget" -ArgumentList $InstallArgs -RedirectStandardOutput $LogFileWingetExe -Wait -NoNewWindow -PassThru

}

#Uninstall function
function Uninstall-App ($AppID, $WingetArgs) {
    #Uninstall App
    Write-Log "-> Uninstalling $AppID..." 'Yellow'
    $UninstallArgs = "uninstall --id $AppID --exact --accept-source-agreements --silent"
    Write-Log "-> Running: `"$Winget`" $WingetArgs"
    Start-Process -FilePath "$Winget" -ArgumentList $UninstallArgs -RedirectStandardOutput $LogFileWingetExe -Wait -NoNewWindow -PassThru
}


<# MAIN #>

#If running as a 32-bit process on an x64 system, re-launch as a 64-bit process
if ("$env:PROCESSOR_ARCHITEW6432" -ne 'ARM64') {
    if (Test-Path "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe") {
        Start-Process "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe" -Wait -NoNewWindow -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command $($MyInvocation.line)"
        Exit $lastexitcode
    }
}



#Run Init Function
Start-Init

#Run WingetCmd Function
Get-WingetCmd

#Run install or uninstall for all apps
Write-Log "App args: $WingetArgs"
foreach ($App_Full in $AppIDs) {
    #Split AppID and Custom arguments
    $AppID = ($App_Full.Trim().Split(' ', 2))

    #Log current App
    Write-Log "Start $AppID processing..." 'Blue'

    #Install or Uninstall command
    if ($Uninstall) {
        Uninstall-App $AppID $WingetArgs
    }
    else {
        #Install
        Install-App $AppID $WingetArgs $CustomArgs $OverrideArgs $Scope
    }

    #Log current App
    Write-Log "$AppID processing finished!`n" 'Blue'
    Start-Sleep 1

}

Write-Log "###   END REQUEST   ###`n" 'Magenta'
Stop-Transcript
Start-Sleep 3
