<#
.SYNOPSIS
Restores the default Notepad application by removing the Notepad++ settings.

.DESCRIPTION
This cmdlet modifies the Windows registry to restore the default Notepad application by removing the Notepad++ settings. It removes the Debugger value and resets the FilterFullPath values.

.EXAMPLE
Replace-NotepadPlusPlusWithNotepad

This example restores the default Notepad application by removing the Notepad++ settings.

.NOTES
Requires administrative privileges to modify the registry.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param ()

# Define the registry path
$registryPath = 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\notepad.exe'

try {
    if ($PSCmdlet.ShouldProcess('Registry', 'Restore default Notepad settings')) {
        # Remove the Debugger value
        try {
            Remove-ItemProperty -Path $registryPath -Name 'Debugger' -Force
            Write-Host 'Removed Debugger setting from Notepad.'
        }
        catch {
            Write-Error "Failed to remove Debugger: $_"
        }

        # Reset FilterFullPath values for Notepad++
        try {
            for ($i = 0; $i -lt 3; $i++) {
                Remove-ItemProperty -Path "$registryPath\$i" -Name 'FilterFullPath' -Force
            }
            Write-Host 'Reset FilterFullPath values for Notepad++.'
        }
        catch {
            Write-Error "Failed to reset FilterFullPath: $_"
        }
    }
}
catch {
    Write-Error "Failed to modify the registry: $_"
}
