# Note that I'm not validating any input or providing any adequate error handling.
# This is just an example, you'll need to add these in yourself.

Param(
    [Parameter(Mandatory = $True, HelpMessage = 'Enter the email address that you want to export')]
    $Mailbox,
    [Parameter(Mandatory = $false, HelpMessage = 'Enter the URL for the user''s OneDrive here. If you don''t enter one, this will be skipped.')]
    $OneDriveURL,
    [Parameter(Mandatory = $True, HelpMessage = 'Enter the folder path where you want to save the PST file. !NO TRAILING BACKSLASH!')]
    $ExportLocation # = ""# you can un-comment the = "" to set a default for this parameter.
)

# Create a search name. You can change this to suit your preference
$SearchName = "$Mailbox PST"

# I'm using the Exchange Online Powershell Module v2. You can install it from an admin session with the following command: Install-Module ExchangeOnlineManagement
# Install Exchange Module
if (-not (Get-Module -Name ExchangeOnlineManagement -ListAvailable)) {
    Install-Module -Name ExchangeOnlineManagement -Force -AllowClobber
}

Write-Host 'Connecting to Exchange Online. Enter your admin credentials in the pop-up (pop-under?) window.'
Connect-IPPSSession

Write-Host 'Creating compliance search...'
if ($null -eq $OneDriveURL) {
    New-ComplianceSearch -Name $SearchName -ExchangeLocation $Mailbox -AllowNotFoundExchangeLocationsEnabled $true #Create a content search, including the the entire contents of the user's email
}
else {
    New-ComplianceSearch -Name $SearchName -ExchangeLocation $Mailbox -SharePointLocation $OneDriveURL -AllowNotFoundExchangeLocationsEnabled $true #Create a content search, including the the entire contents of the user's email and onedrive. If you didn't provide a OneDrive URL, or it wasn't valid, it will be ignored.
}

Write-Host 'Starting compliance search...'
Start-ComplianceSearch -Identity $SearchName #Start the search created above
Write-Host 'Waiting for compliance search to complete...'
for ($SearchStatus; $SearchStatus -notlike 'Completed'; ) {
    #Wait then check if the search is complete, loop until complete
    Start-Sleep -s 2
    $SearchStatus = Get-ComplianceSearch $SearchName | Select-Object -ExpandProperty Status #Get the status of the search
    Write-Host -NoNewline '.' # Show some sort of status change in the terminal
}
Write-Host 'Compliance search is complete!'
Write-Host 'Creating export from the search...'
try {
    New-ComplianceSearchAction -SearchName $SearchName -Export -Format FxStream -ExchangeArchiveFormat PerUserPst -Scope BothIndexedAndUnindexedItems -EnableDedupe $true -SharePointArchiveFormat IndividualMessage -IncludeSharePointDocumentVersions $true -Confirm:$false
}
catch {
    Write-Host 'Export failed. Please check if user has the eDiscovery Manager role assigned. If not, assign it and try again.'
    exit
}
Start-Sleep -s 5 # Arbitrarily wait 5 seconds to give microsoft's side time to create the SearchAction before the next commands try to run against it. I /COULD/ do a for loop and check, but it's really not worth it.

# Check if the export tool is installed for the user, and download if not.
While (-Not ((Get-ChildItem -Path $($env:LOCALAPPDATA + '\Apps\2.0\') -Filter microsoft.office.client.discovery.unifiedexporttool.exe -Recurse).FullName | Where-Object { $_ -notmatch '_none_' } | Select-Object -First 1)) {
    Write-Host 'Downloading Unified Export Tool .'
    Write-Host 'This is installed per-user by the Click-Once installer.'
    # Credit to Jos Verlinde for his code in Load-ExchangeMFA in the Powershell Gallery! All I've done is update the manifest url and remove all the comments
    # Ripped from https://www.powershellgallery.com/packages/Load-ExchangeMFA/1.2
    # In case anyone else has any ClickOnce applications they'd like to automate the install for:
    # If you're looking for where to find a manifest URL, once you have run the ClickOnce application at least once on your computer, the url for the application manifest can be found in the Windows Registry at "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall" (yes, CTR apps are installed per-user).
    # Look through the keys with names that are 16 characters long hex strings. They'll have a string value (REG_SZ) named either "ShortcutAppId" or "UrlUpdateInfo" that contains the URL as the first part of the string.
    $Manifest = 'https://complianceclientsdf.blob.core.windows.net/v16/Microsoft.Office.Client.Discovery.UnifiedExportTool.application'
    $ElevatePermissions = $true
    Try {
        Add-Type -AssemblyName System.Deployment
        Write-Host "Starting installation of ClickOnce Application $Manifest "
        $RemoteURI = [URI]::New( $Manifest , [UriKind]::Absolute)
        if (-not  $Manifest) {
            throw "Invalid ConnectionUri parameter '$ConnectionUri'"
        }
        $HostingManager = New-Object System.Deployment.Application.InPlaceHostingManager -ArgumentList $RemoteURI , $False
        Register-ObjectEvent -InputObject $HostingManager -EventName GetManifestCompleted -Action { 
            New-Event -SourceIdentifier 'ManifestDownloadComplete'
        } | Out-Null
        Register-ObjectEvent -InputObject $HostingManager -EventName DownloadApplicationCompleted -Action { 
            New-Event -SourceIdentifier 'DownloadApplicationCompleted'
        } | Out-Null
        $HostingManager.GetManifestAsync()
        $event = Wait-Event -SourceIdentifier 'ManifestDownloadComplete' -Timeout 15
        if ($event ) {
            $event | Remove-Event
            Write-Host 'ClickOnce Manifest Download Completed'
            $HostingManager.AssertApplicationRequirements($ElevatePermissions)
            $HostingManager.DownloadApplicationAsync()
            $event = Wait-Event -SourceIdentifier 'DownloadApplicationCompleted' -Timeout 60
            if ($event ) {
                $event | Remove-Event
                Write-Host 'ClickOnce Application Download Completed'
            }
            else {
                Write-Error 'ClickOnce Application Download did not complete in time (60s)'
            }
        }
        else {
            Write-Error 'ClickOnce Manifest Download did not complete in time (15s)'
        }
    }
    finally {
        Get-EventSubscriber | Where-Object { $_.SourceObject.ToString() -eq 'System.Deployment.Application.InPlaceHostingManager' } | Unregister-Event
    }
}

$exportexe = ((Get-ChildItem -Path $($env:LOCALAPPDATA + '\Apps\2.0\') -Filter microsoft.office.client.discovery.unifiedexporttool.exe -Recurse).FullName | Where-Object { $_ -notmatch '_none_' } | Select-Object -First 1)

# Gather the URL and Token from the export in order to start the download
# We only need the ContainerURL and SAS Token at a minimum but we're also pulling others to help with tracking the status of the export.
$ExportName = $SearchName + '_Export'
Write-Output $ExportName
do {
    Start-Sleep -s 5
    $ExportDetails = Get-ComplianceSearchAction -Identity $ExportName -IncludeCredential -Details # Get details for the export action

    # This method of splitting the Container URL and Token from $ExportDetails is thanks to schmeckendeugler from reddit: https://www.reddit.com/r/PowerShell/comments/ba4fpu/automated_download_of_o365_inbox_archive/
    # I was using Convert-FromString before, which was slow and terrible. His way is MUCH better.
    $ExportDetailsArray = $ExportDetails.Results.split(';')
    
} until ($null -ne $ExportDetailsArray[18])

$ExportContainerUrl = $ExportDetailsArray[0].trimStart('Container url: ')
$ExportSasToken = $ExportDetailsArray[1].trimStart(' SAS token: ')
$ExportEstSize = ($ExportDetailsArray[18].TrimStart(' Total estimated bytes: ') -as [double])
$ExportTransferred = ($ExportDetailsArray[20].TrimStart(' Total transferred bytes: ') -as [double])
$ExportProgress = $ExportDetailsArray[22].TrimStart(' Progress: ').TrimEnd('%')
$ExportStatus = $ExportDetailsArray[25].TrimStart(' Export status: ')

# Download the exported files from Office 365
Write-Host 'Initiating download'
Write-Host 'Saving export to: ' + $ExportLocation
$Arguments = "-name ""$SearchName""", "-source ""$ExportContainerUrl""", "-key ""$ExportSasToken""", "-dest ""$ExportLocation""", '-trace true'
Start-Process -FilePath "$ExportExe" -ArgumentList $Arguments

# The export is now downloading in the background. You can find it in task manager. Let's monitor the progress.
# If you want to use this as part of a user offboarding script, add your edits above here - Exports can take a lot of time...
# You can even comment this entire section and exit the script if you dont feel the need to monitor the download, it will keep downloading in the background even without the script running.
# This is only monitoring if the process exists, which means if you run multiple exports, this will stay running until they all complete.
# We could possibly utilize sysinternals handle.exe to identify the PID of the process writing to the $Exportlocation and monitor for that specifically, but I'm trying to limit external applications in this example script.
#
# Just an FYI, the export progress is how much data Microsoft has copied into PSTs from the compliance search, not how much the export tool has downloaded.
# We only know the actual size of the download after the $ExportProgress is 100% and $ExportStatus is Completed
# The actual final size of the download is then reflected in $ExportTransferred. Even then, our progress is still a bit inaccurate due to the extra log and temp files created locally, which will probably cause the progress to show over 100%
# We could make this a bit more accurate by just collecting the size of PSTs and files under the OneDrive folder, but I think this brings us close enough for most situations.
while (Get-Process microsoft.office.client.discovery.unifiedexporttool -ErrorAction SilentlyContinue) {
    $Downloaded = Get-ChildItem $ExportLocation\$SearchName -Recurse | Measure-Object -Property Length -Sum | Select-Object -ExpandProperty Sum
    Write-Progress -Id 1 -Activity 'Export in Progress' -Status 'Complete...' -PercentComplete $ExportProgress
    if ('Completed' -notlike $ExportStatus) { Write-Progress -Id 2 -Activity 'Download in Progress' -Status 'Estimated Complete...' -PercentComplete ($Downloaded / $ExportEstSize * 100) -CurrentOperation "$Downloaded/$ExportEstSize bytes downloaded." }
    else { Write-Progress -Id 2 -Activity 'Download in Progress' -Status 'Complete...' -PercentComplete ($Downloaded / $ExportEstSize * 100) -CurrentOperation "$Downloaded/$ExportTransferred bytes downloaded." }
    Start-Sleep 60
    $ExportDetails = Get-ComplianceSearchAction -Identity $ExportName -IncludeCredential -Details # Get details for the export action
    $ExportDetailsArray = $ExportDetails.Results.split(';')
    $ExportEstSize = ($ExportDetailsArray[18].TrimStart(' Total estimated bytes: ') -as [double])
    $ExportTransferred = ($ExportDetailsArray[20].TrimStart(' Total transferred bytes: ') -as [double])
    $ExportProgress = $ExportDetailsArray[22].TrimStart(' Progress: ').TrimEnd('%')
    $ExportStatus = $ExportDetailsArray[25].TrimStart(' Export status: ')
    Write-Host -NoNewline ' .'
}
Write-Host 'Download Complete!'
Pause