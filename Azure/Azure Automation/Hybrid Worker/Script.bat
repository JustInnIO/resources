@echo off
set User=svc.azureautomation

REM Path 1: Azure Connected Machine Agent Tokens
set Path1=%ProgramData%\AzureConnectedMachineAgent\Tokens
if exist "%Path1%" (
    icacls "%Path1%" /grant:r "%User%:(OI)(CI)M"
)

REM Path 2: Hybrid Worker Plugin
set Path2=%SystemDrive%\Packages\Plugins\Microsoft.Azure.Automation.HybridWorker.HybridWorkerForWindows
if exist "%Path2%" (
    icacls "%Path2%" /grant:r "%User%:(OI)(CI)M"
)
