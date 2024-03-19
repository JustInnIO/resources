$Groups = Get-MgGroup -All -Property "DisplayName,AssignedLicenses" | Select-Object DisplayName -ExpandProperty AssignedLicenses
$Groups | Where-object { $_.AssignedLicenses.Count -ne $null } | Select-Object DisplayName, AssignedLicenses
