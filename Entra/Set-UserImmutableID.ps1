# Connect to Graph
Connect-MgGraph

# Get all users from Graph with Immutable ID
$Users = Get-MgUser -All  -property id,onpremisessamaccountname,OnPremisesImmutableId,mail -ConsistencyLevel eventual | Select-Object id,onpremisessamaccountname,OnPremisesImmutableId,mail 

$Users | ForEach-object{
 $_.OnPremisesImmutableId = ([system.convert]::FromBase64String("$($_.OnPremisesImmutableId)") | ForEach-Object ToString X2) -join ' '
}

# Set immutable id as ms-DS-ConsistencyGUID in the AD User
$Users | ForEach-Object {
    $User = $_
    $Mail = $User.Mail
    $ADUser = Get-ADUser -Filter {mail -eq $Mail} -Properties ms-DS-ConsistencyGUID
    if ($ADUser -eq $null) {
        Write-Warning "User $($User.mail) not found in AD"
        return
    }
    if ($ADUser.'ms-DS-ConsistencyGUID' -eq $null) {
        Write-Output "Setting Immutable ID for $($User.mail)"
        Set-ADUser -Identity $ADUser -Replace @{'ms-DS-ConsistencyGUID' = $User.OnPremisesImmutableId}
    }
    else {
        Write-Output "Immutable ID already set for $($User.mail)"
    }
}


