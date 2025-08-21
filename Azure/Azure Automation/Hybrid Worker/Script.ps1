$User = "svc.azureautomation"

# Path 1: Azure Connected Machine Agent Tokens
$Path1 = "`$env:ProgramData\AzureConnectedMachineAgent\Tokens"
if (Test-Path `$Path1) {
    takeown /f "`$Path1" /r /d y
    icacls "`$Path1" /grant:r "$($User):(OI)(CI)M"
}

# Path 2: Hybrid Worker Plugin
$Path2 = "`$env:SystemDrive\Packages\Plugins\Microsoft.Azure.Automation.HybridWorker.HybridWorkerForWindows"
if (Test-Path `$Path2) {
    icacls "`$Path2" /grant:r "$($User):(OI)(CI)M"
} 
