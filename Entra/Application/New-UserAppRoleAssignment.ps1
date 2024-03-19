# DisplayName of the managed Identity
$ManagedIdentity = "UserManagedIdentity"

# Import required modules
if (-not (Get-Command Connect-MgGraph -ErrorAction SilentlyContinue)) {
    Install-Module -Name Microsoft.Graph.Authentication
}
if (-not (Get-Command New-MgServicePrincipalAppRoleAssignment  -ErrorAction SilentlyContinue)) {
    Install-Module -Name Microsoft.Graph.Applications
}

Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Applications

# Connect to Graph with the required permissions
Connect-MgGraph -Scopes "Application.ReadWrite.All", "AppRoleAssignment.ReadWrite.All"

# Get the Managed Identity service principal and the Microsoft Graph service principal
$SPIdentity = Get-MgServicePrincipal -Filter "displayName eq '$ManagedIdentity'" -All
$SPGraph = Get-MgServicePrincipal -Filter "displayName eq 'Microsoft Graph'"-All

# Which permissions should be assigned
$Permissions = @(
    # Advanced queries
    "ThreatHunting.Read.All"
    # SharePoint
    "Sites.Selected"
    # Mail send OPTIONAL
    # Check https://learn.microsoft.com/en-us/graph/auth-limit-mailbox-access for more infos
    # "Mail.Send"
)

foreach ($Permission in $Permissions) {
    # Getting the ID of the Graph permission for assignment
    $GraphPermissionID = ($Msgraph.AppRoles | Where-Object { $_.Value -eq $Permission }).Id

    # Assigning the permission to the managed identity
    New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $SPIdentity.Id -PrincipalId $SPIdentity.Id -ResourceId $SPGraph.Id -AppRoleId $GraphPermissionID
}
