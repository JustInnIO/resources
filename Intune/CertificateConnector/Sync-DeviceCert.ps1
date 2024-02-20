<# 
.SYNOPSIS
    Script to connect to AzureAD and pull all Autopilot devcies and create 'dummy' computer objects in specified OU
    and then run certificates hash synch to query all domain CA's and locate certificate hash and add to altSecurityIdentities attribute

    This script has been pulled together from the work of:

    1. Andrew Blackburn @ sysmansquad  - https://sysmansquad.com/2021/04/27/working-around-nps-limitations-for-aadj-windows-devices/
        - connecting to Azure AD, synching computer objects to Autopilot devices (only)

    2. tcppapi  - https://github.com/tcppapi/AADx509Sync
        - certificate hash syncing 

.DESCRIPTION
    Scripts needs following Graph permissions to run:
    DeviceManagementServiceConfig.Read.All
    DeviceManagementManagedDevices.Read.All

.NOTES
    File Name      : Sync-DeviceCert.ps1
    Version        : 1.0
    Author         : Tobias Schüle - https://justinn.io
    Prerequisite   : Windows PowerShell v5.x,  WindowsAutoPilotIntune, PSPKI
#>

# Only get certs from CA requested by the following user
$RequesterName = "PLACEHOLDER\Intune-NDES"

# App registration Info for connection
$TenantId = "PLACEHOLDER"
$ClientId = "PLACEHOLDER"
$ClientSecret = "PLACEHOLDER"

# Set the OU for computer object creation
$orgUnit = "OU=AADDeviceSync,DC=justinn,DC=io"


$transcriptfile = ".\Transcript-CertSync-Devices\Sync-" + (Get-Date -UFormat %Y-%m-%d-%H-%M-%S) + ".txt"
Start-Transcript -Path $transcriptfile

# Removes old log files
Get-ChildItem –Path ".\Transcript-CertSync-Devices\" -Recurse | Where-Object { ($_.LastWriteTime -lt (Get-Date).AddDays(-7)) } | Remove-Item

# Import PKI Module
Import-Module PSPKI

# Connect to MSGraph with application credentials
Connect-MSGraphApp -Tenant $TenantId -AppId $ClientId -AppSecret $ClientSecret

# Pull latest Autopilot device information
$AutopilotDevices = Get-AutopilotDevice | Select-Object azureActiveDirectoryDeviceId, managedDeviceId, enrollmentState

# Only sync enrolled devices
$AutopilotDevices = $AutopilotDevices | Where-Object { $_.enrollmentState -eq "enrolled" }

# AutoPilot Devices with Cert
foreach ( $CAHost in (Get-CertificationAuthority).ComputerName) {
    [PSCustomObject]$AutoPilotDevicesWithCert += (Get-IssuedRequest -Filter "Request.RequesterName -eq $RequesterName" -CertificationAuthority $CAHost -Property CommonName).CommonName
}

# Create new Autopilot device objects in AD while skipping already existing computer objects and updates the description
Write-Output "Creating new dummy computer objects if necessary..."
foreach ($Device in $AutopilotDevices) {
    $DeviceName = (Invoke-MSGraphRequest -Url "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$($Device.managedDeviceId)" -HttpMethod Get).DeviceName
    if ($ADComputer = Get-ADComputer -Properties * -Filter "Name -eq ""$($Device.azureActiveDirectoryDeviceId)""" -SearchBase $orgUnit -ErrorAction SilentlyContinue) {
        # Changes the description if it doesnt include the current device name
        if ($ADComputer.Description -notmatch $DeviceName) {
            Set-ADComputer -Description $DeviceName -Identity $ADComputer.SAMAccountName -Confirm:$False
            Write-Output "Changed deviceName in Description"
        }
        else {
            Write-Output "Skipping $($Device.azureActiveDirectoryDeviceId) because it already exists with the correct information."
        }
    }
    else {
        # Checks if Device has a certificate in the CA, if not then device is not being created
        if ($AutoPilotDevicesWithCert -contains "$($Device.azureActiveDirectoryDeviceId)") {
            # Create new AD computer object with the devicename as description
            try {
                New-ADComputer -Name "$($Device.azureActiveDirectoryDeviceId)" -SAMAccountName "$($Device.azureActiveDirectoryDeviceId.Substring(0,15))`$" -ServicePrincipalNames "HOST/$($Device.azureActiveDirectoryDeviceId)" -Path $orgUnit -Description $DeviceName
                Write-Output "Computer object created. ($($Device.azureActiveDirectoryDeviceId))"
            }
            catch {
                Write-Error "Error. Skipping computer object creation."
            }
        }
        else {
            Write-Host "Computer object not created because it has no cert. ($($Device.azureActiveDirectoryDeviceId))"
        }
    }
}

Write-Output "Check if devices in AD don't exist in AAD anymore..."

# Checks all dummy devices if they should be deleted, if yes then the description is changed to "ToDelete"
$DummyDevices = Get-ADComputer -Filter * -SearchBase $orgUnit -Properties Description | Select-Object Name, SAMAccountName, Description
foreach ($DummyDevice in $DummyDevices) {
    if ($AutopilotDevices.azureActiveDirectoryDeviceId -contains $DummyDevice.Name) {
        # Write-Output "$($DummyDevice.Name) exists in Autopilot."
    }
    else {
        if ($DummyDevice.Description -ne "ToDelete") {
            Write-Output "$($DummyDevice.Name) does not exist in Autopilot. Adding info to description..."
            Set-ADComputer -Description "ToDelete" -Identity $DummyDevice.SAMAccountName -Confirm:$False
        }
    }
   
}

### CERT SYNC

Write-Output "Starting certificate sync..."
Clear-Variable IssuedCerts -ErrorAction SilentlyContinue
try {
    foreach ($CAHost in (Get-CertificationAuthority).ComputerName) {
        Write-Output "<CERT> Getting all issued certs from '$CAHost' and requested by $RequesterName..."

        # Query is only getting Certs requested by RequestName which is defined at the beginning of the script
        $IssuedRaw = Get-IssuedRequest -Filter "Request.RequesterName -eq $RequesterName" -CertificationAuthority $CAHost -Property RequestID, ConfigString, CommonName, CertificateHash, RawCertificate

        $IssuedCerts += $IssuedRaw | Select-Object -Property RequestID, ConfigString, CommonName, CertificateHash, @{
            name       = 'SANPrincipalName';
            expression = {
                ($(New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @(, [Convert]::FromBase64String($_.RawCertificate))).Extensions | `
                    Where-Object { $_.Oid.FriendlyName -eq "Subject Alternative Name" }).Format(0) -match "^(.*)(Principal Name=)([^,]*)(,?)(.*)$" | Out-Null;
                if ($matches.GetEnumerator() | Where-Object Value -eq "Principal Name=") {
                    $n = ($matches.GetEnumerator() | Where-Object Value -eq "Principal Name=").Name + 1;
                    $matches[$n]
                }
            }
        }
    }
}
catch {
    Write-Output "Error - $($_.Exception.Message)" 
    Write-Output "<CERT> Error getting issued certificates from ADCS servers"
}
try { 
    Write-Output "<CERT> Getting AD objects..."
    $AADx509Devs = Get-ADComputer -Filter '(objectClass -eq "computer")' -SearchBase $orgUnit -Property Name, altSecurityIdentities
}
catch {  
    Write-Output "$($_.Exception.Message)" 
    Write-Output  "<CERT> Error getting AADx509 computers for hash sync"
}

Write-Output "<CERT> Writing certs to computer objects..."
foreach ($dev in $AADx509Devs) {
    $certs = $IssuedCerts | Where-Object SANPrincipalName -Like "host/$($dev.Name)"
    if ($certs) {
        $a = @()
        $b = @()
        foreach ($cert in $certs) {
            $hash = ($cert.CertificateHash) -Replace '\s', ''
            $a += "X509:<SHA1-PUKEY>$hash"
            $b += "($($cert.ConfigString)-$($cert.RequestID))$hash"
        }
        [Array]::Reverse($a)
        try {
            if (!((-Join $dev.altSecurityIdentities) -eq (-Join $a))) {
                [Array]::Reverse($a)
                $ht = @{"altSecurityIdentities" = $a }
                Write-Output "<CERT> Mapping AADx509 computer '$($dev.Name)' to (CA-RequestID) SHA1-hash '$($b -Join ',')'"
                Get-ADComputer -Filter "(servicePrincipalName -like 'host/$($dev.Name)')" | Set-ADComputer -Add $ht
            }
        }
        catch {  
            Write-Output "$($_.Exception.Message)" 
            Write-Output "<CERT> Error mapping AADx509 computer object '$($dev.Name)' to (CA-RequestID) SHA1-hash '$($b -Join ',')'"
        }
    }
}

Write-Output "<CERT> Certificate sync completed"

Stop-Transcript