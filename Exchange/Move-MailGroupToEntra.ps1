<#
.SYNOPSIS
    Migrates mail enabled groups from on-premises to Exchange Online
.DESCRIPTION
    The script migrates mail enabled groups from on-premises to Exchange Online by disabling the AD Sync, creating the group in Exchange Online and adding the members to the group. The script exports the groups to a CSV file and disables the AD Sync. After the AD Sync is disabled, the script starts a sync cycle with Start-ADSyncSyncCycle -PolicyType Delta. After the sync cycle, the script creates the groups in Exchange Online and adds the members to the group. The script also adds additional email addresses that are not the primarysmtpaddress to the group.
    If the export to CSV does not work, the script stops. The script also logs if the AD Sync was disabled, if the group was created in Exchange Online and if the additional email addresses were added to the group.
    The script is used to migrate mail enabled groups from on-premises to Exchange Online.
.NOTES
    File Name      : Move-MailGroupToEntra.ps1
    Version        : 1.0
    Author         : Tobias Schüle - https://justinn.io
    Prerequisite   : Windows PowerShell v5.x, Exchange Online PowerShell Module
#>
 
#region Initalize
# Define Email Address of mail resource to test with one object
$TestEmail = "DoNotUse"
# Define the EntraConnect server
$EntraConnectServer = "entraconnect.justinn.io"
# Define the attribute and value to disable AD Sync
$NoSyncAttribute = "extensionAttribute15"
$NoSyncValue = "NoSync"
 
# Which group types to migrate
# MailUniversalDistributionGroup, MailUniversalSecurityGroup
$RecipientTypeDetails = "MailUniversal"

# Default Managed By
$DefaultManagedBy = "ManagedBy"
 
# Install required modules if not installed
if (-not (Get-Module -Name ExchangeOnlineManagement -ListAvailable)) {
    Install-Module -Name ExchangeOnlineManagement -Force -AcceptLicense -AllowClobber
}
#endregion
 
 
#region Program
# Connecting to Exchange
Connect-ExchangeOnline
 
# If Email Address is set, then only the group with the email address will be migrated
 
 
Write-Output "Getting mail enabled groups in Exchange Online..."
# Getting all synced mail groups
 
if ($TestEmail -match "@") {
    # TEST One Mailbox
    $GroupsRaw = Get-DistributionGroup -ResultSize Unlimited | Select-Object * | Where-Object { $_.IsDirSynced -eq $true -and $_.RecipientTypeDetails -match "$RecipientTypeDetails" } | Where-Object { $_.PrimarySmtpAddress -eq $TestEmail }
}
else {
    # PROD
    $GroupsRaw = Get-DistributionGroup -ResultSize Unlimited | Select-Object * | Where-Object { $_.IsDirSynced -eq $true -and $_.RecipientTypeDetails -match "$RecipientTypeDetails" } 
}
 
# Selecting properties
$Groups = $GroupsRaw | Select-Object Name, ADSyncDisabled, NewGroupCreated, ExternalDirectoryObjectID, ManagedBy, Alias, BccBlocked, Description, DisplayName, HiddenGroupMembershipEnabled, PrimarySmtpAddress, WindowsEmailAddress, MailTip, RequireSenderAuthenticationEnabled, RoomList, GroupType, EmailAddresses, GrantSendOnBehalf, HiddenFromAddressListsEnabled, Members
 
Write-Output "Group count: $($Groups.Count)"
 
# Adding all group members with their email address and changing the ManagedBy object to comma seperated string
Write-Output "Optimizing properties Members and ManagedBy..."
 
$Groups | ForEach-Object {
    # Deleted group members dont return the primarysmtpaddress but the WindowsLiveID
    $GroupMembers = (Get-DistributionGroupMember -Identity $_.Alias).Alias
    $_.Members = if ($GroupMembers.count -ne 0) { ($GroupMembers | Where-Object { $_ -ne "" }) -split -join "," }else { $null }
    $_.ManagedBy = ($_.ManagedBy | Where-Object { $_ -ne "Organization Management" })
}
 
# Export all groups as backup
$Path = "$env:USERPROFILE\Group-Export-$(Get-Date -Format 'yyyyMMdd_HHmm_ss').json"
Write-Output "Exporting group data as Json to $Path"
$Groups | ConvertTo-Json | Out-File $Path -ErrorAction Stop
 
# If the export didnt work, the script is stopped
if (-not (Test-Path -Path $Path)) {
    exit
}
else {
    Write-Output "Groups successfully exported as CSV to $Path"
}
 
# Removing groups from sync
$Groups | ForEach-Object {
    $Group = $_
    $Primary = $Group.PrimarySmtpAddress
    try {
        Get-ADGroup -Filter { mail -eq $Primary } -Properties * | Set-ADGroup -Add @{"$NoSyncAttribute" = $NoSyncValue }
        Write-Output "$($_.PrimarySmtpAddress): AD Sync disabled"
        $_.ADSyncDisabled = "Yes"
        return
    }
    catch {
        Write-Warning "$($Group.PrimarySmtpAddress): AD Sync not disabled due to error"
        $_
    }
            $_.ADSyncDisabled = "Error"
 
}
 
# Starting Sync Cycle
Invoke-Command -ComputerName $EntraConnectServer  -Authentication Kerberos -ScriptBlock { Start-ADSyncSyncCycle -PolicyType Delta }
# Check if sync is done by checking if the object doesnt exist in Entra ID anymore
 
Start-Sleep -Seconds 120
 
 
# Adding new groups
Write-Output "Creating new groups in Exchange Online..."
$Groups | ForEach-Object {
    # Skip groups without members
    if ($_.Members -eq $null) { 
        Write-Output "$($_.PrimarySmtpAddress): No members found in group. Skipping..."
        #return
    }
 
    Write-Output "$($_.PrimarySmtpAddress): Creating group $($_.PrimarySmtpAddress) in Exchange Online..."
 
    # Only run on group where the sync was disabled
    if ($_.ADSyncDisabled -ne "Yes") { 
        #return 
    }
    # Only run when the group currently does not exist
    if (Get-DistributionGroup -Identity $_.Alias) {
        Write-Warning "$($_.PrimarySmtpAddress): Exists in Exchange Online"
        return
    }
    try {
        $NewGroup = @{
            Confirm                            = $false
            Alias                              = $_.Alias
            BccBlocked                         = $_.BccBlocked
            CopyOwnerToMember                  = $_.CopyOwnerToMember
            Description                        = $_.Description
            DisplayName                        = $_.DisplayName
            HiddenGroupMembershipEnabled       = $_.HiddenGroupMembershipEnabled
            #IgnoreNamingPolicy = 
            ManagedBy                          = $DefaultManagedBy
            #MemberDepartRestriction = 
            #MemberJoinRestriction = 
            Members                            = $_.Members
            #ModeratedBy = 
            #ModerationEnabled = 
            Name                               = $_.Name
            Notes                              = $_.Notes
            PrimarySmtpAddress                 = $_.PrimarySmtpAddress
            RequireSenderAuthenticationEnabled = $_.RequireSenderAuthenticationEnabled
            RoomList                           = $_.RoomList
            #SendModerationNotifications = 
            Type                               = "Security"
        }
        New-DistributionGroup @NewGroup | Out-Null
        Write-Output "$($_.PrimarySmtpAddress): Group successfully created in Exchange Online"
        $_.NewGroupCreated = "Yes"
        return
    }
    catch {
        Write-Warning "Error occured while creating group with the following values $NewGroup"
        $_
    }
    $_.NewGroupCreated = "Error"
}
 
 
# Adding additional email addreses that are not the primarysmtpaddress
$Groups | ForEach-Object {
    # Only run on group where the sync was disabled
    if ($_.NewGroupCreated -ne "Yes") { 
        Write-Output "$($_.PrimarySmtpAddress): New group was not created. Skipping..."
    }
    else {
        $Group = $_
        $EmailAddressesCleaned = ($Group.EmailAddresses | Where-Object { $_ -match "SMTP:" }) -split -join ","  #| Where-Object { $_ -notmatch $Group.PrimarySmtpAddress }
 
        Set-DistributionGroup -Identity $Group.Alias -EmailAddresses $EmailAddressesCleaned -Mailtip $Group.MailTip -BypassSecurityGroupManagerCheck
        Write-Output "$($_.PrimarySmtpAddress): Added following email addresses: $EmailAddressesCleaned"
    }
}
#endregion