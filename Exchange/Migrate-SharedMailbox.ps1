<#
.SYNOPSIS
    Migrate shared mailboxes from AD to Exchange Online.
.DESCRIPTION
    This script disables AD Sync for shared mailboxes, restores deleted mailboxes and sets the immutable ID to null.
    The script can be run with the -TestEmail parameter to only test one mailbox.
.NOTES
    File Name      : Migrate-SharedMailbox.ps1
    Version        : 1.0
    Author         : Tobias Schüle
    Prerequisite   : Windows PowerShell v5.x, Exchange Online PowerShell Module
#>

#region Initalize
# Define Email Address of mail resource to test with one object
$TestEmail = "sharedtest@justinn.io"
# Define the EntraConnect server
$EntraConnectServer = "entraconnect.justinn.io"
# Define the attribute and value to disable AD Sync
$NoSyncAttribute = "extensionAttribute15"
$NoSyncValue = "NoSync"

# Install required modules if not installed
if (-not (Get-Module -Name ExchangeOnlineManagement -ListAvailable)) {
    Install-Module -Name ExchangeOnlineManagement -Force -AcceptLicense -AllowClobber
}
if (-not (Get-Module -Name Microsoft.Graph.Identity.DirectoryManagement -ListAvailable)) {
    Install-Module -Name Microsoft.Graph.Identity.DirectoryManagement -Force -AcceptLicense -AllowClobber
}
#endregion

#region Program
# Connecting to Exchange
Connect-ExchangeOnline

# Connecting to graph with reqired permissions
Connect-MgGraph -Scopes "User.Read.All","User.ReadWrite.All","Directory.ReadWrite.All","Directory.AccessAsUser.All"

# Get all shared mailboxes synced from AD
$SharedMailboxes = Get-Mailbox -ResultSize Unlimited | Where-Object {$_.IsDirSynced -eq $true -and $_.RecipientTypeDetails -match "SharedMailbox"}

if ($TestEmail -match "@") {
    # TEST One Mailbox
    $SharedMailboxes = $SharedMailboxes | Where-Object { $_.PrimarySmtpAddress -eq $TestEmail }
}

$SharedMailboxes = $SharedMailboxes | Select-Object DisplayName,MailboxRestored,ImmutableIDSet,ExternalDirectoryObjectId,Alias,PrimarySmtpAddress

# Removing shared mailboxes from sync
$SharedMailboxes | ForEach-Object {
    try {
        Set-ADUser -Identity $_.Alias -Add @{"$NoSyncAttribute" = "$NoSyncValue" }
        Write-Output "$($_.PrimarySmtpAddress): AD Sync disabled"
        $_.ADSyncDisabled = "Yes"
        continue
    }
    catch {
        Write-Warning "$($_.PrimarySmtpAddress): AD Sync not disabled due to error"
        $_
    }
    $_.ADSyncDisabled = "Error"
}

# Starting Sync Cycle
Invoke-Command -ComputerName $EntraConnectServer -Authentication Kerberos -ScriptBlock { Start-ADSyncSyncCycle -PolicyType Delta }
Start-Sleep -Seconds 300


<#
WARNING: 
For Restore-MgDirectoryDeletedItem to restore user and mailbox, the user needs to be deleted from Entra ID. 
If the user was only removed from Exchange Online, the mailbox needs to be restored with Undo-SoftDeletedMailbox
#>

# Recover deleted user in Entra ID with Restore-MgDirectoryDeletedItem
$SharedMailboxes | ForEach-Object {
    $Mailbox = $_
    Write-Output "$($_.PrimarySmtpAddress): Restoring deleted mailbox..."
    try {
        Restore-MgDirectoryDeletedItem -DirectoryObjectId $_.ExternalDirectoryObjectId -ErrorAction Stop
        Write-Output "$($_.PrimarySmtpAddress): Mailbox successfully restored"
        $_.MailboxRestored = "Yes"
        continue
    }
    catch {
        Write-Warning "$($Mailbox.PrimarySmtpAddress): Mailbox not restored due to error"
        $_
    }
    $_.MailboxRestored = "Error"
}

# Recover mailbox in Exchange Online with Undo-SoftDeletedMailbox if user was removed from Exchange Online. Not required if the user was only removed from Entra ID
<#
$SharedMailboxes | ForEach-Object {
    $Mailbox = $_
    Write-Output "$($_.PrimarySmtpAddress): Restoring deleted mailbox..."
    try {
        Undo-SoftDeletedMailbox -Identity $_.PrimarySmtpAddress -Confirm:$false -ErrorAction Stop
        Write-Output "$($_.PrimarySmtpAddress): Mailbox successfully restored"
        $_.MailboxRestored = "Yes"
        continue
    }
    catch {
        Write-Warning "$($Mailbox.PrimarySmtpAddress): Mailbox not restored due to error"
        $_
    }
    $_.MailboxRestored = "Error"
}
#>

# Set immutable ID for shared mailboxes to null
$SharedMailboxes | ForEach-Object {
    Write-Output "$($_.PrimarySmtpAddress): Setting immutable ID to null..."
    try {
        # It is not possible to set the immutable ID to null with the Update-MgUser cmdlet
        # Update-MgUser -UserId $_.ExternalDirectoryObjectId -OnPremisesImmutableId "null" -ErrorAction Stop

        # Use Invoke-GraphRequest to set the immutable ID to null
        Invoke-GraphRequest PATCH -Uri "https://graph.microsoft.com/v1.0/users/$($_.ExternalDirectoryObjectId)" -Body @{"onPremisesImmutableId" = $null} -ErrorAction Stop
        Write-Output "$($_.PrimarySmtpAddress): Immutable ID successfully set to null"
        $_.ImmutableIdSet = "Yes"
        continue
    }
    catch {
        Write-Warning "$($_.PrimarySmtpAddress): Immutable ID not set to null due to error"
        $_
    }
    $_.ImmutableIdSet = "Error"
}
#endregion