# Check that Microsoft.Graph is installed
if (-Not (Get-Module -ListAvailable -Name Microsoft.Graph)) {

    $install = Read-Host 'The Microsoft.Graph PowerShell module is not installed. Do you want to install it now? (Y/n)'

    if ($install -eq '' -or $install -eq 'Y' -or $install -eq 'Yes') {
        If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
            Write-Warning "Administrator permissions are needed to install the Microsoft.Graph PowerShell module.`nPlease re-run this script as an Administrator."
            Exit
        }

        Write-Host 'Installing Microsoft.Graph module...'
        Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force
    }
    else {
        exit
    }
}

Connect-MgGraph -Scopes 'User.Read.All' 

# Get all member enabled users with Entra ID Plan 1 license and synced
$graphUsers = Get-MgUser -All -Property UserPrincipalName, OnPremisesSamAccountName, OnPremisesUserPrincipalName, AssignedPlans -Filter "OnPremisesSyncEnabled eq true and assignedPlans/any(c:c/ServicePlanId eq 41781fb2-bc02-4b7c-bd55-b576c07bb09d and c/capabilityStatus eq 'Enabled') and accountEnabled eq true and mail ne null and userType eq 'Member'" -ConsistencyLevel eventual -Count $count | Select-Object OnPremisesSamAccountName, OnPremisesUserPrincipalName, UserPrincipalName

$results = @()

# Because SamAccountName and UserPrincipalName are not always the same, we need to add both to the file
foreach ($user in $graphUsers) {
    $aduser = New-Object -TypeName PSObject
    $aduser | Add-Member -MemberType NoteProperty -Name Source -Value $($user.OnPremisesSamAccountName)
    $aduser | Add-Member -MemberType NoteProperty -Name Destination -Value $($user.UserPrincipalName)
    $results += $aduser

    # From the OnPrem UserPrincipalName only the part before @ is required for the mapping
    $aduser = New-Object -TypeName PSObject
    $aduser | Add-Member -MemberType NoteProperty -Name Source -Value ($($user.OnPremisesUserPrincipalName) -replace '@.*', '')
    $aduser | Add-Member -MemberType NoteProperty -Name Destination -Value $($user.UserPrincipalName)
    $results += $aduser
}

# Remove duplicates
$results = $results | Select-Object Source, Destination -Unique #| Sort-Object Source

# Export lookup file
$results | Export-Csv "$((Get-Location).Path)\UserLookup.csv" -NoTypeInformation -NoHeader