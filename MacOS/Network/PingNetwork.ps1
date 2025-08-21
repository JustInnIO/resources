# Advanced IP Scanner with parallel processing, error handling and performance optimization
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$NetworkID = "192.168.1",
    [Parameter(Mandatory=$false)] 
    [ValidateRange(1,254)]
    [int]$StartIP = 1,
    [Parameter(Mandatory=$false)]
    [ValidateRange(1,254)] 
    [int]$EndIP = 254,
    [Parameter(Mandatory=$false)]
    [ValidateRange(1,1000)]
    [int]$MaxParallel = 100,
    [Parameter(Mandatory=$false)]
    [int]$PingTimeout = 1000
)

# Performance optimization: Pre-allocate array
$Results = [System.Collections.ArrayList]::new()

# Create runspace pool for parallel processing
$RunspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxParallel)
$RunspacePool.Open()
$Jobs = New-Object System.Collections.ArrayList

# Create job for each IP
$StartIP..$EndIP | ForEach-Object {
    $PowerShell = [powershell]::Create().AddScript({
        param($IP, $Timeout)
        
        try {
            # Optimized ping using native .NET
            $Ping = New-Object System.Net.NetworkInformation.Ping
            $Response = $Ping.Send("$using:NetworkID.$IP", $Timeout)
            
            [PSCustomObject]@{
                'IP' = "$using:NetworkID.$IP"
                'Status' = if($Response.Status -eq 'Success'){'Online'}else{'Offline'}
                'ResponseTime' = $Response.RoundtripTime
            }
        }
        catch {
            [PSCustomObject]@{
                'IP' = "$using:NetworkID.$IP" 
                'Status' = 'Error'
                'ResponseTime' = $null
            }
        }
    }).AddArgument($_).AddArgument($PingTimeout)

    $PowerShell.RunspacePool = $RunspacePool

    [void]$Jobs.Add(@{
        PowerShell = $PowerShell
        Handle = $PowerShell.BeginInvoke()
    })
}

# Collect results
Write-Verbose "Scanning $($Jobs.Count) IP addresses..."

foreach($Job in $Jobs) {
    try {
        $Result = $Job.PowerShell.EndInvoke($Job.Handle)
        [void]$Results.Add($Result)
        
        # Real-time status
        Write-Host ("{0,-15} : {1,-8} : {2}ms" -f $Result.IP, $Result.Status, $Result.ResponseTime) -ForegroundColor $(
            switch($Result.Status) {
                'Online' {'Green'}
                'Offline' {'Red'} 
                default {'Yellow'}
            }
        )
    }
    catch {
        Write-Warning "Job failed: $_"
    }
    finally {
        $Job.PowerShell.Dispose()
    }
}

$RunspacePool.Close()
$RunspacePool.Dispose()

# Final sorted output
$Results | Sort-Object {[version]$_.IP} | Format-Table -AutoSize

Write-Verbose "Scan complete. Found $($Results.Count) hosts."