Param(
    [Parameter(Mandatory = $True, HelpMessage = 'Enter the email address of the mailbox you want to clear')]
    $Mailbox
)

# Define Mailbox in Script
#$Mailbox = "tobias@justinn.io"

# Create a search name. You can change this to suit your preference
$SearchName = "Clear Mailbox $Mailbox"

# Only search for emails
$MatchQuery = "kind:email"

# I'm using the Exchange Online Powershell Module v2. You can install it from an admin session with the following command: Install-Module ExchangeOnlineManagement
# Install Exchange Module
if (-not (Get-Module -Name ExchangeOnlineManagement -ListAvailable)) {
    Install-Module -Name ExchangeOnlineManagement -Force -AllowClobber
}

Write-Host "Connecting to Exchange Online. Enter your admin credentials in the pop-up (pop-under?) window."
Connect-IPPSSession

Write-Host "Creating compliance search..."
New-ComplianceSearch -Name $SearchName -ExchangeLocation $Mailbox -AllowNotFoundExchangeLocationsEnabled $true -ContentMatchQuery $MatchQuery  #Create a content search, including the the entire contents of the user's email

Write-Host "Starting compliance search..."
Start-ComplianceSearch -Identity $SearchName #Start the search created above
Write-Host "Waiting for compliance search to complete..."
for ($SearchStatus; $SearchStatus -notlike "Completed"; ) {
    #Wait then check if the search is complete, loop until complete
    Start-Sleep -s 10
    $SearchStatus = Get-ComplianceSearch $SearchName | Select-Object -ExpandProperty Status #Get the status of the search
    Write-Host -NoNewline "." # Show some sort of status change in the terminal
}
Write-Host "Compliance search is complete!"

[int]$ItemsFound = (Get-ComplianceSearch -Identity $SearchName).Items

If ($ItemsFound -gt 0) {
    $Stats = Get-ComplianceSearch -Identity $SearchName | Select-Object -Expand SearchStatistics | Convertfrom-JSON
    $Data = $Stats.ExchangeBinding.Sources | Where-Object { $_.ContentItems -gt 0 }
    Write-Host ""
    Write-Host "Total Items found matching query:" $ItemsFound 
    Write-Host ""
    Write-Host "Items found in the following mailboxes"
    Write-Host "--------------------------------------"
    Foreach ($D in $Data) {
        Write-Host ("{0} has {1} items of size {2}" -f $D.Name, $D.ContentItems, $D.ContentSize)
    }
    Write-Host " "
    [int]$Iterations = 0; [int]$ItemsProcessed = 0
    While ($ItemsProcessed -lt $ItemsFound) {
        $Iterations++
        Write-Host ("Deleting items...({0})" -f $Iterations)
        New-ComplianceSearchAction -SearchName $SearchName -Purge -PurgeType HardDelete -Confirm:$False | Out-Null
        $SearchActionName = $SearchName + "_Purge"
        While ((Get-ComplianceSearchAction -Identity $SearchActionName).Status -ne "Completed") {
            # Let the search action complete
            Start-Sleep -Seconds 5 
        }
        $ItemsProcessed = $ItemsProcessed + 10 # Can remove a maximum of 10 items per mailbox
        # Remove the search action so we can recreate it
        Remove-ComplianceSearchAction -Identity $SearchActionName -Confirm:$False -ErrorAction SilentlyContinue 
    }
}
Else {
    Write-Host "The search didn't find any items..." 
}

Write-Host "All done!"