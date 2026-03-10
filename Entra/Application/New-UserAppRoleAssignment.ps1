# DisplayName of the managed Identity
$ManagedIdentityDisplayName = 'AzureAutomationAccount'

# Import required modules
if (-not (Get-Command Connect-MgGraph -ErrorAction SilentlyContinue)) {
    Install-Module -Name Microsoft.Graph.Authentication
}
if (-not (Get-Command New-MgServicePrincipalAppRoleAssignment -ErrorAction SilentlyContinue)) {
    Install-Module -Name Microsoft.Graph.Applications
}

Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Applications

# Connect to Graph with the required permissions
Connect-MgGraph -Scopes 'Application.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All'

# Get the Managed Identity service principal
$SPIdentity = Get-MgServicePrincipal -Filter "displayName eq '$ManagedIdentityDisplayName'" -All

# Resource service principals — loaded on demand
$ResourceSPs = @{
    Graph    = Get-MgServicePrincipal -Filter "displayName eq 'Microsoft Graph'" -All                          # AppId: 00000003-0000-0000-c000-000000000000
    Exchange = Get-MgServicePrincipal -Filter "AppId eq '00000002-0000-0ff1-ce00-000000000000'" -All            # Office 365 Exchange Online
}

# Known Exchange Online permission values — add more as needed
$ExchangePermissions = @(
    'Exchange.ManageAsApp'
    'full_access_as_app'
    'Mail.Read'
    'Mail.ReadWrite'
    'Calendars.Read'
    'Calendars.ReadWrite'
    'Contacts.Read'
    'Contacts.ReadWrite'
    'MailboxSettings.Read'
    'MailboxSettings.ReadWrite'
)

# Which permissions should be assigned
$Permissions = @(
    # ── Graph permissions ──
    # "ThreatHunting.Read.All"
    # "Sites.Selected"
    # "Files.ReadWrite.All"
    # "User.Read.All"
    # "Contacts.ReadWrite"
    # "Group.ReadWrite.All"
    # "GroupMember.ReadWrite.All"
    # "Mail.Send"                    # https://learn.microsoft.com/en-us/graph/auth-limit-mailbox-access
    # "DeviceManagementServiceConfig.Read.All"

    # ── Exchange Online permissions ──
    "Exchange.ManageAsApp"           # Required for Exchange Online PowerShell via managed identity
    # "full_access_as_app"           # Full mailbox access (use with caution)
)

foreach ($Permission in $Permissions) {
    # Determine the target resource service principal
    if ($Permission -in $ExchangePermissions) {
        $TargetSP = $ResourceSPs.Exchange
        $ResourceName = 'Exchange Online'
    }
    else {
        $TargetSP = $ResourceSPs.Graph
        $ResourceName = 'Microsoft Graph'
    }

    # Resolve the AppRole ID
    $AppRoleId = ($TargetSP.AppRoles | Where-Object { $_.Value -eq $Permission }).Id

    if (-not $AppRoleId) {
        Write-Warning "Permission '$Permission' not found on $ResourceName — skipping."
        continue
    }

    # Assign the permission
    try {
        New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $SPIdentity.Id -PrincipalId $SPIdentity.Id -ResourceId $TargetSP.Id -AppRoleId $AppRoleId
        Write-Host "Assigned '$Permission' ($ResourceName)" -ForegroundColor Green
    }
    catch {
        if ($_.Exception.Message -like '*already exists*') {
            Write-Host " '$Permission' ($ResourceName) already assigned — skipping." -ForegroundColor Yellow
        }
        else {
            Write-Error "Failed to assign '$Permission' ($ResourceName): $_"
        }
    }
}