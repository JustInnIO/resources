$SourceDomainDN = 'dc=justinn,=dc=io'
 
# Install Graph Module if missing
if (-not (Get-Command Connect-MgGraph -ErrorAction SilentlyContinue)) {
    Install-Module -Name Microsoft.Graph.Users
}
 
# Connect to MgGraph if not connected
if ($null -eq (Get-MgContext)) {
    Connect-MgGraph -Scopes 'User.Read.All', 'User.ReadWrite.All'
}
 
$Users = Get-MgUser -Property ID, UserPrincipalName, OnPremisesDistinguishedName, OnPremisesImmutableId, proxyAddresses, UsageLocation, OnPremisesSamAccountName -All 
$Users = $Users | Where-Object { $_.OnPremisesDistinguishedName -match $SourceDomainDN -and $_.ProxyAddresses -ne $null -and $_.OnPremisesImmutableId -ne $null }
 
$NotFoundUsers = @()
$Users | ForEach-Object {
    $ADUser = Get-ADUser -Filter { UserPrincipalName -eq $_.UserPrincipalName } -ErrorAction SilentlyContinue
    if ($null -eq $ADUser) {
        Write-Warning "User $($_.UserPrincipalName) not found in AD"
        # Adding all not found users to an array
        $NotFoundUsers += $_ | Select-Object UserPrincipalName, OnPremisesDistinguishedName
        return
    }
 
    $_.ProxyAddresses | ForEach-Object {
        [String]$ProxyAddress = $_
        if ($_ -match 'SMTP' -and $_ -notmatch 'mail.onmicrosoft.com') {
            $ADUser | Set-ADUser -Add @{ProxyAddresses = $ProxyAddress } #-WhatIf
            Write-Output "$($ADUser.UserPrincipalName) - Added ProxyAddress: $_"
        }
    }
}
 
Write-Output 'Following users were not found in AD:'