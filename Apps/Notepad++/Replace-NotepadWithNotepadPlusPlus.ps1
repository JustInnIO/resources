<#
.SYNOPSIS
Replaces the default Notepad application with Notepad++.

.DESCRIPTION
This cmdlet modifies the Windows registry to replace the default Notepad application with Notepad++. It sets the debugger value and filter full path values to point to Notepad++.

.PARAMETER NotepadPlusPlusPath
The path to the Notepad++ executable. If not specified, the cmdlet will use the default installation path.

.EXAMPLE
Replace-NotepadWithNotepadPlusPlus -NotepadPlusPlusPath "C:\Program Files\Notepad++\notepad++.exe"

This example replaces the default Notepad application with Notepad++ using the specified path.

.NOTES
Requires administrative privileges to modify the registry.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory = $false)]
    [string]$NotepadPlusPlusPath = "$env:ProgramFiles\Notepad++\notepad++.exe"
)

# Check if the Notepad++ executable exists
if (-Not (Test-Path -Path $NotepadPlusPlusPath)) {
    Write-Error "Notepad++ executable not found at path: $NotepadPlusPlusPath"
    return
}

# Define the registry path
$registryPath = 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\notepad.exe'

try {
    if ($PSCmdlet.ShouldProcess('Registry', 'Replace Notepad with Notepad++')) {
        # Set the Debugger value
        Set-ItemProperty -Path $registryPath -Name 'Debugger' -Value "`"$NotepadPlusPlusPath`" -notepadStyleCmdline -z" -Force

        # Set FilterFullPath values
        for ($i = 0; $i -lt 3; $i++) {
            Set-ItemProperty -Path "$registryPath\$i" -Name 'FilterFullPath' -Value $NotepadPlusPlusPath -Force
        }

        Write-Host 'Notepad replaced with Notepad++ successfully.'
    }
}
catch {
    Write-Error "Failed to modify the registry: $_"
}
