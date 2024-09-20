# Description: Export Hybrid Group Immutable ID

$outputCSV = 'C:\temp\groups.csv'

$defaultProperties = @('samAccountName', 'distinguishedName', 'objectGUID', 'mS-DS-ConsistencyGuid')
$Groups = Get-ADGroup -Filter * -Properties $defaultProperties -ErrorAction Stop
$results = @()
if ($Groups -eq $null) {
       Write-Error 'Groups not found'
}
else {
       # For each groups get the data
       foreach ($Group in $Groups) {
              $objectGUIDValue = [GUID]$group.'objectGUID'
              $mSDSConsistencyGuidValue = 'N/A'
              if ($group.'mS-DS-ConsistencyGuid' -ne $null) {
                     $mSDSConsistencyGuidValue = [GUID]$group.'mS-DS-ConsistencyGuid'
              }
              $adgroup = New-Object -TypeName PSObject
              $adgroup | Add-Member -MemberType NoteProperty -Name samAccountName -Value $($group.'samAccountName')
              $adgroup | Add-Member -MemberType NoteProperty -Name distinguishedName -Value $($group.'distinguishedName')
              $adgroup | Add-Member -MemberType NoteProperty -Name objectGUID -Value $($objectGUIDValue)
              $adgroup | Add-Member -MemberType NoteProperty -Name mS-DS-ConsistencyGuid -Value $($mSDSConsistencyGuidValue)
              $results += $adgroup
       }
}

Write-Host 'Exporting group to output file'
$results | Export-Csv "$outputCsv" -NoTypeInformation