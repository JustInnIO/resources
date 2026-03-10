# Managed Identity
# Please change this value to the managed identity you want to assign the permission to.
$ManagedIdentityDisplayName = 'SHESharePointSyncTest'

# SharePoint Site ID
# You can find out the ID by addint the following text behind the site url /_api/site/id?
$SharePointSiteID = 'b5900994-c452-43cc-91b5-892f22ca6df9'

# Import required modules
if (-not (Get-Command Connect-MgGraph -ErrorAction SilentlyContinue)) {
	Install-Module -Name Microsoft.Graph.Authentication
}
if (-not (Get-Command New-MgSitePermission -ErrorAction SilentlyContinue)) {
	Install-Module -Name Microsoft.Graph.Sites
}

if (-not (Get-Command Get-MgServicePrincipal -ErrorAction SilentlyContinue)) {
	Install-Module -Name Microsoft.Graph.Applications
}

Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Sites
Import-Module Microsoft.Graph.Applications

# Connect to Graph with the required permissions
Connect-MgGraph -Scope 'Sites.FullControl.All', 'Application.ReadWrite.All'

# Getting the ID of the Managed Identity with the DisplayName
$ManagedIdentityID = (Get-MgServicePrincipal -Filter "displayName eq '$ManagedIdentityDisplayName'" -All).AppId

$params = @{
	roles               = @(
		'write'
	)
	grantedToIdentities = @(
		@{
			application = @{
				id          = $ManagedIdentityID
				displayName = $ManagedIdentityDisplayName
			}
		}
	)
}

New-MgSitePermission -SiteId $SharePointSiteID -BodyParameter $params -ErrorAction Stop