<#
.SYNOPSIS
    Updates distribution list memberships based on user attributes.
.DESCRIPTION
    This script synchronizes distribution list memberships based on user attributes in Microsoft 365.
    It retrieves users with specific attributes and adds/removes them from distribution lists.
.NOTES
    Version: 1.0
    Required modules: ExchangeOnlineManagement, Microsoft.Graph,Microsoft.Graph.Beta
    Required permissions: Exchange admin, User.Read.All
#>

# Connect to Exchange Online and Microsoft Graph
Connect-ExchangeOnline -ManagedIdentity -Organization "yourtenant.onmicrosoft.com"
Connect-MgGraph -Identity

# Define the groups and filters
$groupsToUpdate = @(
    
    @{
        GroupId = "location.branch1@company.com"
        Filter  = { $_.OnPremisesExtensionAttributes.ExtensionAttribute2 -eq "BR1" }
    },
    @{
        GroupId = "location.branch2@company.com"
        Filter  = { $_.OnPremisesExtensionAttributes.ExtensionAttribute2 -eq "BR2" }
    },
    # Additional location groups can be defined here
    
    @{
        GroupId = "department.hr@company.com"
        Filter  = { 
            ($_.OnPremisesExtensionAttributes.ExtensionAttribute3 -eq "HR" -or
            $_.OnPremisesExtensionAttributes.ExtensionAttribute3 -eq "HR Management") -and
            $_.CompanyName -eq "Main Company Ltd."
        }
    },
    @{
        GroupId = "role.administration@company.com"
        Filter  = { $_.OnPremisesExtensionAttributes.ExtensionAttribute3 -eq "Administration" }
    },
    @{
        GroupId = "admin.maincompany@company.com"
        Filter  = { $_.OnPremisesExtensionAttributes.ExtensionAttribute3 -eq "Administration" -and
            $_.CompanyName -eq "Main Company Ltd." }
    },
    @{
        GroupId = "admin.subsidiary@company.com"
        Filter  = { $_.OnPremisesExtensionAttributes.ExtensionAttribute3 -eq "Administration" -and
            $_.CompanyName -eq "Subsidiary Company Ltd." }
    },
    @{
        GroupId = "role.projectmanager@company.com"
        Filter  = { $_.OnPremisesExtensionAttributes.ExtensionAttribute3 -eq "Project Management" }
    },
    @{
        GroupId = "role.areamanager@company.com"
        Filter  = { $_.OnPremisesExtensionAttributes.ExtensionAttribute3 -eq "Area Management" }
    },
    @{
        GroupId = "employees.division3@company.com"
        Filter  = { $_.CompanyName -eq "Division Three GmbH" }
    },
    @{
        GroupId = "management@company.com"
        Filter  = { 
            $_.OnPremisesExtensionAttributes.ExtensionAttribute3 -eq "Branch Management" -or 
            $_.OnPremisesExtensionAttributes.ExtensionAttribute3 -eq "Regional Management" -or
            $_.OnPremisesExtensionAttributes.ExtensionAttribute4 -eq "Executive Management" -or
            $_.OnPremisesExtensionAttributes.ExtensionAttribute4 -eq "Department Management" 
        } 
    },
    @{
        GroupId = "all.employees@company.com"
        Filter  = { 
            $_.CompanyName -eq "Division Three GmbH" -or
            $_.CompanyName -eq "Division Two GmbH" -or
            $_.CompanyName -eq "Division One Ltd." -or
            $_.CompanyName -eq "Subsidiary Company Ltd." -or
            $_.CompanyName -eq "Main Company Ltd." -or
            $_.CompanyName -eq "Temporary Staffing Ltd."
        } 
    }
)

# Iterate through each group and update members
foreach ($group in $groupsToUpdate) {
    $groupId = $group.GroupId
    Write-Output "Working on $groupId"
    $filter = $group.Filter

    # Get current members of the group
    $currentMembers = Get-DistributionGroupMember -Identity $groupId | Select-Object -ExpandProperty PrimarySmtpAddress

    # Get all users in the organization matching the filter
    $allUsers = Get-MgBetaUser -All -Filter "accountEnabled eq true and mail ne null" -ConsistencyLevel eventual -Count $count | Where-Object $filter

    # Determine users to add and remove
    $usersToAdd = $allUsers | Where-Object { $_.Mail -notin $currentMembers }
    $usersToRemove = $currentMembers | Where-Object { $_ -notin $allUsers.Mail }

    # Add new users to the group
    foreach ($user in $usersToAdd) {
        If ($user.Mail -notin $currentMembers) {
            Add-DistributionGroupMember -Identity $groupId -Member $user.Mail -BypassSecurityGroupManagerCheck
            Write-Output "Added user $($user.Mail) to group $groupId"
        }
        else {
            Write-Verbose "User $($user.Mail) already a member of $groupId"
        }
    }

    # Remove users from the group
    foreach ($user in $usersToRemove) {
        try {
            Remove-DistributionGroupMember -Identity $groupId -Member $user -BypassSecurityGroupManagerCheck -Confirm:$false -ErrorAction Stop
            Write-Output "Removed user $($user) from group $groupId"
        }
        catch {
            Write-Output "Unable to remove user $user from group $groupId: $_"
        }
    }
    Write-Output "Finished processing $groupId"
}

# Disconnect from Exchange Online & Graph
Disconnect-ExchangeOnline -Confirm:$false
Disconnect-MgGraph