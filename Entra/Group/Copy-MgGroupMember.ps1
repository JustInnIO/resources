# Describe cmdlet
<#
.SYNOPSIS
Copies all members from a source group to a destination group using Microsoft Graph.

.DESCRIPTION
This script copies all members from a source group to a destination group using Microsoft Graph. 
The script first checks if the destination group exists, and if not, it creates it. 
Then it retrieves the members of the source group and adds them to the destination group.

.PARAMETER sourceGroup
The name of the source group to copy members from.

.PARAMETER destinationGroup
The name of the destination group to copy members to.

.EXAMPLE
Copy-MgGroupMember -sourceGroup "SourceGroup" -destinationGroup "DestinationGroup"
Copies all members from the group "SourceGroup" to the group "DestinationGroup".
#>

param(
    [string]$sourceGroup,
    [string]$destinationGroup
)
$VerbosePreference = 'Continue'

# Import required modules
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Groups

# Connect to MgGraph if not connected
if ($null -eq (Get-MgContext)) {
    Connect-MgGraph
}
else {
    Write-Verbose 'Already connected to Microsoft Graph'
}

function New-GroupIfNotExist {
    param(
        [string]$GroupName
    )
    
    $group = Get-MgGroup -Filter "displayName eq '$GroupName'" 
    if ($null -eq $group) {
        $newGroup = New-MgGroup -DisplayName $GroupName -MailEnabled:$false -MailNickname $GroupName -SecurityEnabled
        Write-Verbose "Group '$GroupName' created with ID: $($newGroup.Id)"
        return $newGroup.Id
    }
    else {
        Write-Verbose "Group '$GroupName' already exists with ID: $($group.Id)"
        return $group.Id
    }
}

function Copy-GroupMembers {
    param(
        [string]$SourceGroupId,
        [string]$DestinationGroupId
    )

    Write-Verbose "Getting members of group '$sourceGroup'..."
    $members = Get-MgGroupMember -GroupId $SourceGroupId -All
    Write-Verbose "Member count: $($members.Count)"

    foreach ($member in $members) {
        try {
            # Depending on the member type (user, group, etc.), you might need to adjust the object to pass to New-MgGroupMember
            New-MgGroupMember -GroupId $DestinationGroupId -DirectoryObjectId $member.Id
            Write-Verbose "Member $($member.Id) added to group '$destinationGroup'"
        }
        catch {
            Write-Error "Error adding member $($member.DisplayName) to group '$destinationGroup': $_"
        }
    }
}

# Main script execution
$destinationGroupId = if (Get-MgGroup -Filter "displayName eq '$destinationGroup'") {
    (Get-MgGroup -Filter "displayName eq '$destinationGroup'" | Select-Object -ExpandProperty Id)
    Write-Verbose "Group '$destinationGroup' already exists"
}
else { 
    New-GroupIfNotExist -GroupName $destinationGroup 
    Write-Verbose "Group '$destinationGroup' created"
}


$sourceGroupId = (Get-MgGroup -Filter "displayName eq '$sourceGroup'" | Select-Object -ExpandProperty Id)

Write-Verbose "Copying members from group '$sourceGroup' to group '$destinationGroup'..."
Copy-GroupMembers -SourceGroupId $sourceGroupId -DestinationGroupId $destinationGroupId