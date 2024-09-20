# Connect to Graph
Connect-MgGraph

# Get all users from Graph with Immutable ID
$Users = Get-MgUser -All -Property id, onpremisessamaccountname, OnPremisesImmutableId, mail, UserPrincipalName -ConsistencyLevel eventual | Select-Object id, onpremisessamaccountname, OnPremisesImmutableId, mail, UserPrincipalName

$Users | ForEach-Object {
    $_.OnPremisesImmutableId = ([system.convert]::FromBase64String("$($_.OnPremisesImmutableId)")) 
}

# Set immutable id as ms-DS-ConsistencyGUID in the AD User
$Users | ForEach-Object {
    $User = $_
    $UserPrincipalName = $User.UserPrincipalName
    $ADUser = Get-ADUser -Filter { UserPrincipalName -eq $UserPrincipalName } -Properties ms-DS-ConsistencyGUID
    if ($ADUser -eq $null) {
        Write-Warning "User $UserPrincipalName not found in AD"
        return
    }
    if ($ADUser.'ms-DS-ConsistencyGUID' -eq $null) {
        Write-Output "Setting Immutable ID for $UserPrincipalName"
        Set-ADUser -Identity $ADUser -Replace @{'ms-DS-ConsistencyGUID' = $User.OnPremisesImmutableId }
    }
    else {
        Write-Output "Immutable ID already set for $UserPrincipalName"
    }
}


