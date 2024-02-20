<#
.SYNOPSIS
    Script connects to PKI and checks for Certificate requested by the Intune Certificate Connector
    Scripts writes the user certificates into the user object
    No connection to M365 / AAD is needed

.DESCRIPTION
    Required permissions:
    Read/Write attribute altSecurityIdentifier in Active Directory
    Read on CA to read all certificates
    Following Modules are required:
    Install-Module PSPKI -Scope AllUsers -Force -AllowClobber

.NOTES
    File Name      : Migrate-SharedMailbox.ps1
    Version        : 1.0
    Author         : Tobias Schüle
    Prerequisite   : Windows PowerShell v5.x, PSPKI
#>

# Only get certs from CA requested by the following user
$RequesterName = "PLACEHOLDER\Intune-NDES"

$transcriptfile = ".\Transcript-CertSync-User\Sync-" + (Get-Date -UFormat %Y-%m-%d-%H-%M-%S) + ".txt"
Start-Transcript -Path $transcriptfile

# Removes old log files
Get-ChildItem –Path ".\Transcript-CertSync-User\" -Recurse | Where-Object { ($_.LastWriteTime -lt (Get-Date).AddDays(-7)) } | Remove-Item

# Import PKI Module
Import-Module PSPKI

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
    $ADUsers = Get-ADUser -Filter "(UserPrincipalName -Like '*')" -Property Name, altSecurityIdentities
}
catch {  
    Write-Output "$($_.Exception.Message)" 
    Write-Output  "<CERT> Error getting AADx509 users for certificate sync"
}

Write-Output "<CERT> Writing certs to user objects..."
foreach ($user in $ADUsers) {
    $certs = $IssuedCerts | Where-Object SANPrincipalName -Like "$($user.UserPrincipalName)"
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
            if (!(-Join $user.altSecurityIdentities) -eq (-Join $a)) {
                [Array]::Reverse($a)
                $ht = @{"altSecurityIdentities" = $a }
                Write-Host "<CERT> Mapping AD user '$($user.UserPrincipalName)' to (CA-RequestID) SHA1-hash '$($b -Join ',')'"
                $user | Set-ADUser -Add $ht
            }
        }
        catch {
            Write-Host "$($_.Exception.Message)" 
            Write-Host "<CERT> Error mapping AD user object '$($user.UserPrincipalName)' to (CA-RequestID) SHA1-hash '$($b -Join ',')'"
        }
    }
}
Write-Output "<CERT> Certificate user sync completed"

Stop-Transcript