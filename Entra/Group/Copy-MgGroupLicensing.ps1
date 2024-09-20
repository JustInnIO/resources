param(
    [string]$sourceGroup,
    [string]$destinationGroup
)
# Connect to MgGraph if not connected
if ($null -eq (Get-MgContext)) {
    Connect-MgGraph
}


function Copy-GroupLicenses {
    param(
        [string]$sourceGroupId,
        [string]$destinationGroupId
    )

    $sourceLicenses = Get-MgGroup -GroupId $sourceGroupId -Property 'AssignedLicenses' | Select-Object -ExpandProperty AssignedLicenses
    if ($null -eq $sourceLicenses -or $sourceLicenses.Count -eq 0) {
        Write-Host 'No licenses found for the source group.'
        return
    }

    foreach ($license in $sourceLicenses) {
        try {
            $licenseToAdd = @{
                'addLicenses'    = @(
                    @{
                        'disabledPlans' = $license.DisabledPlans
                        'skuId'         = $license.SkuId
                    }
                )
                'removeLicenses' = @()
            }

            Set-MgGroupLicense -GroupId $destinationGroupId -BodyParameter $licenseToAdd
            Write-Host "License $($license.SkuId) copied to destination group."
        }
        catch {
            Write-Error "Failed to assign license to destination group: $_"
        }
    }
}

$sourceGroupId = (Get-MgGroup -Filter "displayName eq '$sourceGroup'" | Select-Object -ExpandProperty Id)
$destinationGroupId = (Get-MgGroup -Filter "displayName eq '$destinationGroup'" | Select-Object -ExpandProperty Id)

Copy-GroupLicenses -sourceGroupId $sourceGroupId -destinationGroupId $destinationGroupId
