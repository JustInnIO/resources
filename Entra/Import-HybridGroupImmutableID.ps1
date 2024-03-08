<#
.SYNOPSIS
This script will take DN of a group as input and the CSV file that was generated by the Import-Group script.
It copies either the objectGUID or the mS-DS-ConsistencyGuid value from the CSV file to the given object.
#>
$inputCSV = "C:\temp\groups.csv"

$Groups = Import-Csv -Path $inputCsv -ErrorAction Stop
foreach ($Group in $Groups) {
       $dn = $Group.DistinguishedName
       $msDSConsistencyGuid = $Group.'mS-DS-ConsistencyGuid'
       $objectGuid = [GUID] $Group.'objectGUID'
       
       # If the group has no mS-DS-ConsistencyGuid then use the objectGuid
       if ($msDSConsistencyGuid -eq "N/A") {
              $msDSConsistencyGuid = $objectGuid
       }

       # If the group doesnt have the value already then change it
       if ((Get-ADGroup -Identity $dn -Properties 'mS-DS-ConsistencyGuid').'mS-DS-ConsistencyGuid' -ne $msDSConsistencyGuid) {
              Write-Output "Setting mS-DS-ConsistencyGuid for $dn"
              Set-ADGroup -Identity $dn -Replace @{'mS-DS-ConsistencyGuid' = $msDSConsistencyGuid } -ErrorAction Stop  
       }
       else {
              Write-Output "mS-DS-ConsistencyGuid already set for $dn"
       }
}