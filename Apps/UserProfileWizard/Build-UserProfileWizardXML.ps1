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

# Get all member enabled users with Entra ID Plan 1 license
$graphUsers = Get-MgUser -All -Property UserPrincipalName, Id, AssignedPlans, DisplayName -Filter "OnPremisesSyncEnabled eq true and assignedPlans/any(c:c/ServicePlanId eq 41781fb2-bc02-4b7c-bd55-b576c07bb09d and c/capabilityStatus eq 'Enabled') and accountEnabled eq true and mail ne null and userType eq 'Member'" -ConsistencyLevel eventual -Count $count | Select-Object UserPrincipalName, Id, DisplayName


# Get the tenant details
$Tenant = Get-MgOrganization

# Create the XML file
$xmlSettings = New-Object System.Xml.XmlWriterSettings
$xmlSettings.Indent = $true
$xmlSettings.IndentChars = '    '

$xmlWriter = [System.XML.XmlWriter]::Create("$((Get-Location).Path)\ForensiTAzureID.xml", $xmlSettings)

# Write the XML Declaration and set the XSL
$xmlWriter.WriteStartDocument()
$xmlWriter.WriteProcessingInstruction('xml-stylesheet', "type='text/xsl' href='style.xsl'")

# Start the Root Element 
$xmlWriter.WriteStartElement('ForensiTAzureID')

# Write the tenant details as attributes
$xmlWriter.WriteAttributeString('ObjectId', $($Tenant.Id))
$xmlWriter.WriteAttributeString('Name', $($Tenant.VerifiedDomains.Name))
$xmlWriter.WriteAttributeString('DisplayName', $($Tenant.DisplayName))

# Parse the data
ForEach ($graphUser in $graphUsers) {
    $xmlWriter.WriteStartElement('User')

    $xmlWriter.WriteElementString('UserPrincipalName', $($graphUser.UserPrincipalName))
    $xmlWriter.WriteElementString('ObjectId', $($graphUser.Id))
    $xmlWriter.WriteElementString('DisplayName', $($graphUser.DisplayName))

    $xmlWriter.WriteEndElement()
}

$xmlWriter.WriteEndElement()

# Close the XML Document
$xmlWriter.WriteEndDocument()
$xmlWriter.Flush()
$xmlWriter.Close()


Write-Host "Graph user ID file created: $((Get-Location).Path)\ForensiTAzureID.xml"
